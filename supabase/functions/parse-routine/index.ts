import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import * as XLSX from "https://esm.sh/xlsx@0.18.5"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    // This function writes with the service-role client, which bypasses
    // RLS entirely — the Flutter UI hiding the upload screen from non-admins
    // is not real access control, since anyone with a valid session token
    // could call this endpoint directly. Verify the caller actually holds
    // an upload-authorized role before touching any data.
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "")
    if (!jwt) {
      return new Response(JSON.stringify({ error: "Missing authorization." }), { status: 401, headers: corsHeaders })
    }
    const { data: authData, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !authData?.user) {
      return new Response(JSON.stringify({ error: "Invalid or expired session." }), { status: 401, headers: corsHeaders })
    }
    const { data: callerProfile } = await supabase.from("profiles").select("role").eq("id", authData.user.id).maybeSingle()
    const uploadAuthorizedRoles = ["admin", "super_admin", "dept_admin", "teacher"]
    if (!callerProfile || !uploadAuthorizedRoles.includes(callerProfile.role)) {
      return new Response(JSON.stringify({ error: "Not authorized to upload routines." }), { status: 403, headers: corsHeaders })
    }

    const contentType = req.headers.get("content-type") || ""
    // Two input shapes:
    //  - multipart/form-data with a `file` (Excel) — parsed here, cheap.
    //  - application/json with pre-extracted `lines` (PDF) — the app
    //    extracts PDF text on-device (Syncfusion) and sends just the text,
    //    because full PDF-to-text parsing (pdf.js/unpdf) in this edge
    //    function reliably exceeded its CPU/time budget on multi-page
    //    routine PDFs and crashed the function (HTTP 546). Phones have no
    //    such limit, so the heavy step now happens client-side.
    let rows: string[][] = []
    let lines: string[] = []
    let type = "schedule"

    if (contentType.includes("application/json")) {
      const body = await req.json()
      type = (body.type || "schedule").toLowerCase()
      lines = Array.isArray(body.lines) ? body.lines.map((l: unknown) => String(l).trim()).filter(Boolean) : []
      rows = lines.map((l) => [l])
    } else {
      const formData = await req.formData()
      const file = formData.get("file") as File
      type = ((formData.get("type") as string) || "schedule").toLowerCase()
      if (!file) return new Response(JSON.stringify({ error: "No file provided" }), { status: 400, headers: corsHeaders })
      if (!/\.(xlsx|xls)$/i.test(file.name)) {
        return new Response(JSON.stringify({ error: "This endpoint only accepts Excel files directly. PDFs must be sent as extracted text (the app does this automatically)." }), { status: 400, headers: corsHeaders })
      }
      rows = await extractRowsFromExcel(file)
      lines = rows.map((r) => r.join(" "))
    }

    if (rows.length === 0) {
      return new Response(JSON.stringify({ error: "Could not extract any rows from the file. For PDFs, ensure it is text-based, not scanned; for Excel, ensure the first sheet has the data." }), { status: 400, headers: corsHeaders })
    }

    // A routine PDF/sheet can produce hundreds of rows (600-900+ for a full
    // department routine). Upserting them one row per awaited request took
    // 150+ seconds and blew the edge function's compute budget (HTTP 546
    // WORKER_RESOURCE_LIMIT) well before finishing. Supabase's upsert
    // accepts an array, so batch rows into a handful of bulk requests
    // instead of one request per row — a couple of round-trips instead of
    // hundreds.
    // Postgres rejects an upsert batch that hits the same conflict target
    // twice in one statement ("ON CONFLICT DO UPDATE command cannot affect
    // row a second time"), which can happen if parsing produces two
    // near-identical rows for the same slot — de-dupe on the conflict key
    // first (keeping the last occurrence) so a batch never fails outright.
    function dedupeByKey(records: any[], onConflict: string): any[] {
      const keyFields = onConflict.split(",")
      const byKey = new Map<string, any>()
      for (const r of records) byKey.set(keyFields.map((f) => String(r[f])).join("|"), r)
      return [...byKey.values()]
    }

    const batchErrors: string[] = []
    async function batchUpsert(table: string, records: any[], onConflict: string, batchSize = 200): Promise<number> {
      const deduped = dedupeByKey(records, onConflict)
      let inserted = 0
      for (let i = 0; i < deduped.length; i += batchSize) {
        const batch = deduped.slice(i, i + batchSize)
        const { error, count } = await supabase.from(table).upsert(batch, { onConflict, count: "exact" })
        if (!error) inserted += count ?? batch.length
        else if (batchErrors.length < 3) batchErrors.push(error.message)
      }
      return inserted
    }

    // A re-upload replaces the previous routine/schedule for whatever it
    // covers — rows that no longer appear in the new file must be removed,
    // not left behind as stale data (e.g. a cancelled class staying on
    // students' schedules forever). `scopeFields` defines the "replace
    // unit" (e.g. department+semester for class routines) — every existing
    // row within that same scope whose full key isn't in the new upload
    // gets deleted. An empty scopeFields means "replace the whole table"
    // (used for transport routes, which is one university-wide file).
    async function deleteObsolete(table: string, newRecords: any[], keyFields: string[], scopeFields: string[]): Promise<number> {
      if (newRecords.length === 0) return 0
      const keyOf = (r: any) => keyFields.map((f) => String(r[f] ?? "")).join("|")
      const newKeys = new Set(newRecords.map(keyOf))

      const scopeCombos = new Map<string, any>()
      for (const r of newRecords) {
        const combo: Record<string, any> = {}
        for (const f of scopeFields) combo[f] = r[f]
        scopeCombos.set(scopeFields.map((f) => String(r[f] ?? "")).join("|"), combo)
      }
      if (scopeCombos.size === 0) scopeCombos.set("", {})

      let deleted = 0
      for (const combo of scopeCombos.values()) {
        let query = supabase.from(table).select(keyFields.join(","))
        for (const f of scopeFields) query = query.eq(f, combo[f])
        const { data: existing, error } = await query
        if (error || !existing) continue
        for (const row of existing as any[]) {
          if (newKeys.has(keyOf(row))) continue
          let delQuery = supabase.from(table).delete()
          for (const f of keyFields) delQuery = delQuery.eq(f, row[f])
          const { error: delErr } = await delQuery
          if (!delErr) deleted++
        }
      }
      return deleted
    }

    const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY")

    // department/semester are populated directly on profiles by
    // handle_new_user(), so filtering profiles works for those. batch is
    // NOT — only students.batch_label is ever set — so batch-scoped exam
    // notifications must resolve ids via the students table instead.
    async function resolveUserIdsByDeptSemester(department?: string, semester?: number): Promise<string[]> {
      let query = supabase.from("profiles").select("id")
      if (department) query = query.eq("department", department)
      if (semester) query = query.eq("semester", semester)
      const { data: rows } = await query
      return (rows ?? []).map((r: { id: string }) => r.id)
    }

    async function resolveUserIdsByBatch(batch?: string): Promise<string[]> {
      if (!batch) return []
      const { data: rows } = await supabase.from("students").select("profile_id").eq("batch_label", batch)
      return (rows ?? []).map((r: { profile_id: string }) => r.profile_id)
    }

    async function notifyUsers(userIds: string[], title: string, message: string, deepLink: string) {
      try {
        if (userIds.length === 0) return
        await supabase.from("user_notifications").insert(userIds.map((uid: string) => ({
          user_id: uid, title, body: message, category: "routine", deep_link_route: deepLink,
        })))
        if (!ONESIGNAL_REST_KEY) return
        await fetch("https://onesignal.com/api/v1/notifications", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Basic ${ONESIGNAL_REST_KEY}` },
          body: JSON.stringify({
            app_id: "2ae8d7b3-8999-4054-b185-2256b290993c",
            include_aliases: { external_id: userIds },
            target_channel: "push",
            headings: { en: title },
            contents: { en: message },
          }),
        })
      } catch {
        // Best-effort: never fail the upload response over a notification hiccup.
      }
    }

    if (type === "transport") {
      const routes = parseTransportRows(rows)
      if (routes.length === 0) {
        return new Response(JSON.stringify({ error: "No transport routes recognized in file." }), { status: 400, headers: corsHeaders })
      }
      // parseTransportRows attaches working fields (route_details, stops,
      // to_dsc_times, from_dsc_times) that aren't real transport_routes
      // columns — sending them straight through would make PostgREST reject
      // the whole upsert with "column does not exist". Only route_number/
      // route_name/departure_times/is_active are real columns; stops go to
      // their own table below.
      const routeRows = routes.map((r) => ({
        route_number: r.route_number, route_name: r.route_name,
        departure_times: r.departure_times, is_active: r.is_active,
      }))
      const inserted = await batchUpsert("transport_routes", routeRows, "route_number")
      const removed = await deleteObsolete("transport_routes", routeRows, ["route_number"], [])

      // Persist the per-route stop order parsed from route_details — this
      // previously never happened at all, so transport_stops stayed empty
      // for every route regardless of how many times transport data was
      // uploaded, which is why the map/find-route screens had nothing to
      // show. No lat/long is available from the source sheet (it only has
      // stop names, not GPS coordinates), so those stay null; the map
      // falls back to its "no path yet" state until coordinates exist.
      let stopsInserted = 0
      const { data: routeIdRows } = await supabase.from("transport_routes")
        .select("id, route_number").in("route_number", routes.map((r) => r.route_number))
      const routeIdByNumber = new Map((routeIdRows ?? []).map((r: { id: string; route_number: string }) => [r.route_number, r.id]))
      for (const route of routes) {
        const routeId = routeIdByNumber.get(route.route_number)
        if (!routeId || !Array.isArray(route.stops) || route.stops.length === 0) continue
        await supabase.from("transport_stops").delete().eq("route_id", routeId)
        const stopRows = route.stops.map((s: { name: string }, i: number) => ({
          route_id: routeId, stop_name: s.name, stop_order: i,
        }))
        const { error, count } = await supabase.from("transport_stops").insert(stopRows, { count: "exact" })
        if (!error) stopsInserted += count ?? stopRows.length
        else if (batchErrors.length < 3) batchErrors.push(error.message)
      }

      const transportUserIds = await resolveUserIdsByDeptSemester()
      await notifyUsers(transportUserIds, "Transport routes updated",
        "Bus routes and times have been updated — check the Transport tab.", "/transport")
      return new Response(JSON.stringify({ success: true, slotsInserted: inserted, slotsRemoved: removed, stopsInserted, totalParsed: routes.length, type: "transport", batchErrors }), { headers: corsHeaders })
    }

    if (type === "class_routine") {
      const slots = parseClassRoutineLines(lines)
      if (slots.length === 0) {
        return new Response(JSON.stringify({ error: "No class routine sessions recognized in file.", linesPreview: lines.slice(0, 5) }), { status: 400, headers: corsHeaders })
      }
      const keyFields = ["subject_code", "day_of_week", "start_time", "room_number", "batch", "section", "department", "semester"]
      const inserted = await batchUpsert("schedule_slots", slots, keyFields.join(","))
      const removed = await deleteObsolete("schedule_slots", slots, keyFields, ["department", "semester"])
      const dept = slots[0]?.department
      const sem = slots[0]?.semester
      const classUserIds = await resolveUserIdsByDeptSemester(dept, sem)
      await notifyUsers(classUserIds, "Class routine updated",
        `Your ${dept ?? ""} semester ${sem ?? ""} class routine has been updated.`, "/schedule")
      return new Response(JSON.stringify({ success: true, slotsInserted: inserted, slotsRemoved: removed, totalParsed: slots.length, type: "class_routine", batchErrors }), { headers: corsHeaders })
    }

    if (type === "exam_routine") {
      const exams = parseExamRoutineLines(lines)
      if (exams.length === 0) {
        return new Response(JSON.stringify({ error: "No exam routine entries recognized in file.", linesPreview: lines.slice(0, 5) }), { status: 400, headers: corsHeaders })
      }
      const keyFields = ["subject_code", "exam_date", "start_time", "batch", "exam_type"]
      const inserted = await batchUpsert("exams", exams, keyFields.join(","))
      const removed = await deleteObsolete("exams", exams, keyFields, ["batch", "exam_type"])
      const batch = exams[0]?.batch
      const examUserIds = await resolveUserIdsByBatch(batch)
      await notifyUsers(examUserIds, "Exam routine updated",
        `Your ${exams[0]?.exam_type === "mid" ? "midterm" : "final"} exam routine has been updated.`, "/schedule")
      return new Response(JSON.stringify({ success: true, slotsInserted: inserted, slotsRemoved: removed, totalParsed: exams.length, type: "exam_routine", batchErrors }), { headers: corsHeaders })
    }

    const slots = parseScheduleRows(rows)
    if (slots.length < 3) {
      return new Response(JSON.stringify({ error: "Routine format not recognized. Found fewer than 3 slots.", rowsPreview: rows.slice(0, 5) }), { status: 400, headers: corsHeaders })
    }
    const scheduleKeyFields = ["subject_code", "day_of_week", "start_time", "department", "semester"]
    const inserted = await batchUpsert("schedule_slots", slots, scheduleKeyFields.join(","))
    const removed = await deleteObsolete("schedule_slots", slots, scheduleKeyFields, ["department", "semester"])
    const legacyUserIds = await resolveUserIdsByDeptSemester(slots[0]?.department, slots[0]?.semester)
    await notifyUsers(legacyUserIds, "Schedule updated",
      "Your class schedule has been updated.", "/schedule")
    return new Response(JSON.stringify({ success: true, slotsInserted: inserted, slotsRemoved: removed, totalParsed: slots.length, type: "schedule", batchErrors }), { headers: corsHeaders })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})

// ---------------------------------------------------------------------
// Excel extraction — returns rows of stringified cells (first sheet).
// ---------------------------------------------------------------------
async function extractRowsFromExcel(file: File): Promise<string[][]> {
  const buffer = await file.arrayBuffer()
  const wb = XLSX.read(new Uint8Array(buffer), { type: "array" })
  const sheet = wb.Sheets[wb.SheetNames[0]]
  const json: unknown[][] = XLSX.utils.sheet_to_json(sheet, { header: 1, blankrows: false })
  return json.map((row) => row.map((cell) => (cell ?? "").toString().trim()))
}


function parseScheduleRows(rows: string[][]): any[] {
  const text = rows.map((r) => r.join(" ")).join(" ")
  const slots: any[] = []
  const dayMap: Record<string, number> = { sat:0, sun:1, mon:2, tue:3, wed:4, thu:5 }
  const timeRegex = /(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})/g
  const dayRegex = /\b(sat|sun|mon|tue|wed|thu)\w*/gi
  const subjectRegex = /\b([A-Z]{2,4}\s?\d{3,4}[A-Z]?)\b/g
  const roomRegex = /\b(\d{1,2}[-–]\d{3,4})\b/g

  const days = [...text.matchAll(dayRegex)].map(m => m[1].toLowerCase().substring(0, 3))
  const times = [...text.matchAll(timeRegex)].map(m => ({ start: m[1], end: m[2] }))
  const subjects = [...text.matchAll(subjectRegex)].map(m => m[1])
  const roomsFound = [...text.matchAll(roomRegex)].map(m => m[1])

  const count = Math.min(days.length, times.length, subjects.length)
  for (let i = 0; i < count; i++) {
    const dayNum = dayMap[days[i]] ?? 0
    const [building, room] = roomsFound[i] ? roomsFound[i].split(/[-–]/) : ['4', '101']
    slots.push({
      subject: subjects[i],
      subject_code: subjects[i],
      teacher_name: 'TBA',
      room_number: room || '101',
      building: `Building ${building || '4'}`,
      start_time: times[i].start + ':00',
      end_time: times[i].end + ':00',
      day_of_week: dayNum,
      credit_hours: 3,
      department: 'CSE',
      semester: 1,
      is_cancelled: false,
    })
  }
  return slots
}

// ---------------------------------------------------------------------
// Class routine grid (e.g. "CSE Class Routine V4.2 Summer-2026.pdf"):
// a table of Room rows x 6 daily time-slot columns, repeated per day
// section header (SATURDAY, SUNDAY, ...). Each occupied cell reads
// "<Room> <COURSE_CODE>(<batch>_<section>) <TeacherInitials>"; empty
// cells just repeat the room name with nothing after it. Because the
// room name is repeated once per slot column on every physical row, it
// acts as a natural column delimiter — splitting a line on repeats of
// its own leading room token yields exactly one chunk per time slot.
// ---------------------------------------------------------------------
const DAY_NAMES: Record<string, number> = {
  saturday: 0, sunday: 1, monday: 2, tuesday: 3, wednesday: 4, thursday: 5, friday: 6,
}
const ROOM_START = /\b(?:KT|ANX\d{0,2}|G\d+|SH|CTBA|EMBEDLAB-KT|IOT LAB-KT)-?\d+[A-Za-z()]*/

// Strips the stray artifacts PDF/Excel extraction tends to leave behind
// (double spaces from column gaps, orphan punctuation, control characters)
// without touching legitimate characters in names — used on every
// extracted room/teacher/course/stop string so the UI shows clean,
// human-readable values instead of raw scrape noise.
function cleanName(s: string): string {
  return s
    .replace(/\s+/g, " ")
    .replace(/^[\s\-_,.;:()<>]+|[\s\-_,.;:()<>]+$/g, "")
    .trim()
}

function parseClassRoutineLines(lines: string[]): any[] {
  const slots: any[] = []
  let currentDay: number | null = null
  let slotTimes: { start: string; end: string }[] = []
  const timeHeaderRegex = /(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})/g
  const courseRegex = /\b([A-Z]{2,6}\d{3})\(([A-Za-z0-9]+)_([A-Za-z0-9().]+?)\)\s+([A-Za-z_]{1,10})\b/g

  for (const rawLine of lines) {
    const line = rawLine.trim()
    if (!line) continue

    const dayMatch = Object.keys(DAY_NAMES).find((d) => new RegExp(`^${d}\\b`, "i").test(line))
    if (dayMatch) { currentDay = DAY_NAMES[dayMatch]; slotTimes = []; continue }

    if (/^room\s+course\s+teacher/i.test(line)) continue

    const timeMatches = [...line.matchAll(timeHeaderRegex)]
    if (timeMatches.length >= 4 && /^\d/.test(line)) {
      slotTimes = timeMatches.map((m) => ({ start: m[1], end: m[2] }))
      continue
    }

    if (currentDay === null || slotTimes.length === 0) continue
    if (!ROOM_START.test(line)) continue

    // Split into per-slot-column chunks on every recurrence of a room token.
    const chunks = line.split(new RegExp(`(?=${ROOM_START.source})`))
      .map((c) => c.trim()).filter(Boolean)
    if (chunks.length === 0) continue

    const roomMatch = chunks[0].match(ROOM_START)
    const room = cleanName(roomMatch ? roomMatch[0] : chunks[0].split(/\s+/)[0])

    chunks.forEach((chunk, i) => {
      if (i >= slotTimes.length) return
      const matches = [...chunk.matchAll(courseRegex)]
      for (const m of matches) {
        const code = cleanName(m[1])
        const batch = cleanName(m[2])
        const section = cleanName(m[3])
        const teacher = cleanName(m[4])
        slots.push({
          subject: code,
          subject_code: code,
          teacher_name: teacher,
          teacher_initial: teacher,
          room_number: room,
          building: room.split("-")[0],
          start_time: slotTimes[i].start + ":00",
          end_time: slotTimes[i].end + ":00",
          day_of_week: currentDay,
          credit_hours: 3,
          department: "CSE",
          semester: 1,
          batch,
          section,
          is_cancelled: false,
        })
      }
    })
  }
  return slots
}

// ---------------------------------------------------------------------
// Exam routine (mid/final term PDFs, e.g. "Midterm Examination Routine"):
// a grid of Date/Day headers, "Slot A/B/C: <start> – <end>" time headers,
// and per-slot blocks of "<CODE><digits>: <title> [<credit-hours-code>]
// Batch-<NN>". We track the most recent date/day and slot-time context
// and attach every course match found after them to that context, so
// courses spanning multiple lines (title wraps) still resolve correctly.
// ---------------------------------------------------------------------
function parseExamRoutineLines(lines: string[]): any[] {
  // Titles and credit-hour brackets often wrap across several PDF text
  // lines (e.g. "CSE326\nSocial and Professional Issues\nin Computing\n
  // [730]\n\nBatch-65"), so line-by-line matching misses most courses.
  // Instead scan the whole flattened text with a regex that can span
  // newlines, and resolve each match's date/slot by nearest preceding
  // marker offset rather than by which line it's on.
  const fullText = lines.join("\n")
  const exams: any[] = []
  const dateRegex = /\b(\d{1,2})\/(\d{1,2})\/(\d{4})\b/g
  const slotTimeRegex = /(\d{1,2}:\d{2})\s*(?:am|pm)?\s*[-–]\s*(\d{1,2}:\d{2})\s*(am|pm)/gi
  const courseRegex = /\b([A-Z]{2,4}\d{3}):?\s*([\s\S]{0,80}?)\[(\d+)\][\s\S]{0,20}?Batch-(\w+)/g
  const examType = /midterm|mid[\s-]?term/i.test(fullText) ? "mid" : "final"

  const dateMarkers = [...fullText.matchAll(dateRegex)].map((m) => ({
    index: m.index!,
    date: `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`,
  }))
  const slotMarkers = [...fullText.matchAll(slotTimeRegex)].map((m) => ({ index: m.index!, start: m[1] }))

  const nearestBefore = <T extends { index: number }>(markers: T[], idx: number): T | null => {
    let best: T | null = null
    for (const m of markers) { if (m.index <= idx) best = m; else break }
    return best
  }

  let lastDateIdx = -1
  let seenSinceDate = 0
  // How many slot-time markers precede this date block — used to offset
  // the per-course cycling counter so it lines up with that day's own
  // Slot A/B/C times rather than always starting from slot index 0.
  for (const m of fullText.matchAll(courseRegex)) {
    const idx = m.index!
    const [, code, title, , batch] = m
    const dateMarker = nearestBefore(dateMarkers, idx)
    if (!dateMarker) continue
    if (dateMarker.index !== lastDateIdx) { lastDateIdx = dateMarker.index; seenSinceDate = 0 }

    const slotsForDay = slotMarkers.filter((s) => s.index >= dateMarker.index &&
      (dateMarkers.find((d) => d.index > dateMarker.index)?.index ?? Infinity) > s.index)
    const slot = slotsForDay.length > 0 ? slotsForDay[seenSinceDate % slotsForDay.length] : null

    exams.push({
      subject: cleanName(title) || code,
      subject_code: cleanName(code),
      exam_date: dateMarker.date,
      start_time: slot ? slot.start + ":00" : null,
      end_time: null,
      exam_type: examType,
      batch: cleanName(batch),
      department: "CSE",
      is_retake: /\bRE\b/.test(m[0]),
    })
    seenSinceDate++
  }
  return exams
}

const isTimeStr = (s: string) => /\d{1,2}:\d{2}(?::\d{2})?\s?(?:AM|PM|am|pm)?/.test(s)
const firstTime = (s: string): string | null => {
  const m = s.match(/\d{1,2}:\d{2}(?::\d{2})?\s?(?:AM|PM|am|pm)?/)
  return m ? m[0].trim() : null
}
const findCol = (header: string[], patterns: RegExp[]): number => {
  for (let i = 0; i < header.length; i++) for (const p of patterns) if (p.test(header[i] ?? "")) return i
  return -1
}

function parseTransportRows(rows: string[][]): any[] {
  // Shape A — the real DIU transport sheet: Route No | Start Time (To DSC)
  // | Route Name | Route Details (free text, stops separated by "<>" or
  // ">") | Departure Time (From DSC), with each route spanning several
  // rows (one per daily trip) and route_number/name/details blank on
  // continuation rows. Detected by header text, not fixed column
  // position, so column order/count can vary between uploads.
  const headerRowIdx = rows.findIndex((r) => findCol(r, [/route\s*(no|number)/i]) !== -1)
  if (headerRowIdx !== -1 && rows[headerRowIdx].length > 1) {
    const header = rows[headerRowIdx]
    const routeNoIdx = findCol(header, [/route\s*(no|number)/i])
    const startTimeIdx = findCol(header, [/start\s*time/i])
    const routeNameIdx = findCol(header, [/route\s*name/i])
    const routeDetailsIdx = findCol(header, [/route\s*detail/i])
    const departureTimeIdx = findCol(header, [/departure\s*time/i])

    if (startTimeIdx !== -1 || departureTimeIdx !== -1) {
      const byRoute = new Map<string, any>()
      let lastKey: string | null = null
      for (let i = headerRowIdx + 1; i < rows.length; i++) {
        const row = rows[i]
        if (row.every((c) => !c || !c.trim())) continue
        // Multi-page exports often repeat the column header partway through
        // the sheet (e.g. "Route No | Route Name | Route Details" showing up
        // again on a new page) — without this guard that repeated header
        // gets ingested as if it were a real route.
        if (/^route\s*(no|number)?$/i.test((row[routeNoIdx] ?? "").trim())) continue
        const routeNo = (row[routeNoIdx] ?? "").trim()
        const key = routeNo || lastKey
        if (!key) continue
        lastKey = routeNo || lastKey

        let entry = byRoute.get(key)
        if (!entry) {
          entry = { route_number: key, route_name: "", route_details: "", to_dsc_times: [] as string[], from_dsc_times: [] as string[], stops: [] as any[], is_active: true }
          byRoute.set(key, entry)
        }
        const routeName = routeNameIdx >= 0 ? (row[routeNameIdx] ?? "").trim() : ""
        if (routeName) entry.route_name = routeName
        const routeDetails = routeDetailsIdx >= 0 ? (row[routeDetailsIdx] ?? "").trim() : ""
        if (routeDetails) entry.route_details = routeDetails

        const startVal = startTimeIdx >= 0 ? (row[startTimeIdx] ?? "").trim() : ""
        if (startVal && isTimeStr(startVal)) {
          const t = firstTime(startVal)
          if (t && !entry.to_dsc_times.includes(t)) entry.to_dsc_times.push(t)
        }
        const depVal = departureTimeIdx >= 0 ? (row[departureTimeIdx] ?? "").trim() : ""
        if (depVal && isTimeStr(depVal)) {
          const t = firstTime(depVal)
          if (t && !entry.from_dsc_times.includes(t)) entry.from_dsc_times.push(t)
        }
      }
      for (const entry of byRoute.values()) {
        if (entry.route_details) {
          // Collapse only consecutive duplicate stop names (a stray extra
          // "<>" splitting one stop into two identical entries is a common
          // sheet artifact) — a route legitimately passing the same
          // landmark twice non-consecutively (loop routes) stays intact.
          entry.stops = entry.route_details.split(/<>|>/).map((s: string) => cleanName(s)).filter(Boolean)
            .filter((name: string, i: number, arr: string[]) => i === 0 || name !== arr[i - 1])
            .map((name: string) => ({ name, time: null }))
        }
        entry.route_name = entry.route_name ? cleanName(entry.route_name) : entry.route_number
        // departure_times kept for any older UI/reports still reading it.
        entry.departure_times = entry.to_dsc_times.length ? entry.to_dsc_times : null
      }
      return [...byRoute.values()].filter(isRealRoute)
    }
  }

  // Shape B — a stop x time grid: Route Number | Route Name | <Stop 1> |
  // <Stop 2> | ... | <Stop N>, each stop column holding that route's time
  // at that stop. Continuation rows with blank route number/name (merged
  // cells) are forward-filled from the last seen route.
  const routes: any[] = []
  const timeRegex = /\d{1,2}:\d{2}(?::\d{2})?\s?(?:AM|PM|am|pm)?/g

  const isHeaderRow = (row: string[]) => /^route\s*(no|number)?$/i.test(row[0] ?? "")
  const headerRow = rows.find(isHeaderRow)
  const stopNames = headerRow ? headerRow.slice(2).map((h) => h.trim()).filter(Boolean) : []

  const byRouteNumber = new Map<string, any>()
  let lastRouteNumber: string | null = null

  for (const row of rows) {
    if (row.length === 1) {
      // Flattened PDF blob: scrape repeating "<num> <name> <times...>" chunks.
      const blob = row[0]
      const chunkRegex = /\b(\d{1,3})\b\s+([A-Za-z][A-Za-z .'-]{2,40}?)\s+((?:\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)?[,;\s]*)+)/g
      for (const m of blob.matchAll(chunkRegex)) {
        const times = [...m[3].matchAll(timeRegex)].map(t => t[0].trim())
        if (times.length === 0) continue
        routes.push({
          route_number: m[1],
          route_name: m[2].trim(),
          departure_times: times,
          stops: [],
          is_active: true,
        })
      }
      continue
    }

    if (isHeaderRow(row)) continue
    if (row.every((c) => !c || !c.trim())) continue

    const [rawRouteNumber, rawRouteName, ...rest] = row
    const routeNumber = (rawRouteNumber || "").trim()
    const routeName = (rawRouteName || "").trim()

    const isContinuation = !routeNumber && !routeName && lastRouteNumber
    const key = isContinuation ? lastRouteNumber! : routeNumber
    if (!key) continue
    lastRouteNumber = routeNumber || lastRouteNumber

    const stops = stopNames
      .map((name, i) => ({ name, time: (rest[i] ?? "").trim() }))
      .filter((s) => isTimeStr(s.time))

    const times = rest.join(",").split(/[,;]/).map((t) => t.trim()).filter((t) => isTimeStr(t))

    const existing = byRouteNumber.get(key)
    if (existing) {
      if (routeName) existing.route_name = routeName
      for (const s of stops) if (!existing.stops.some((e: any) => e.name === s.name)) existing.stops.push(s)
      for (const t of times) if (!existing.departure_times?.includes(t)) (existing.departure_times ??= []).push(t)
    } else {
      byRouteNumber.set(key, {
        route_number: key,
        route_name: routeName || key,
        departure_times: times.length ? times : null,
        stops,
        is_active: true,
      })
    }
  }

  routes.push(...byRouteNumber.values())
  return routes.filter(isRealRoute)
}

// Section titles/labels ("Friday Schedule @ DSC", "Shuttle service") and
// stray repeated headers occasionally survive row-detection and would
// otherwise show up in the app as a "route" with nothing in it — a route
// with no stops and no times at all is never real data.
function isRealRoute(r: any): boolean {
  const headerLike = /^route\s*(no|number|name|detail)/i
  if (headerLike.test(String(r.route_number ?? "")) || headerLike.test(String(r.route_name ?? ""))) return false
  const hasRealStop = Array.isArray(r.stops) && r.stops.some((s: any) => !headerLike.test(String(s?.name ?? "")))
  const hasTimes = (r.to_dsc_times?.length ?? 0) > 0 || (r.from_dsc_times?.length ?? 0) > 0 || (r.departure_times?.length ?? 0) > 0
  return hasRealStop || hasTimes
}
