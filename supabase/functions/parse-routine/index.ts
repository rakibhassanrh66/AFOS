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
      // parseTransportRows attaches a working field (route_details) that
      // isn't a real transport_routes column — sending it straight through
      // would make PostgREST reject the whole upsert with "column does not
      // exist". route_number/route_name/departure_times/to_dsc_times/
      // from_dsc_times/is_active are all real columns though (confirmed
      // live against the schema); to_dsc_times/from_dsc_times were
      // previously dropped here on the wrong assumption that they weren't
      // real columns, which silently stopped every re-upload from ever
      // refreshing either direction's schedule — the UI's "Departure Times
      // (To DSC)" panel was reading the now-stale/empty to_dsc_times while
      // the real data kept landing in departure_times instead. stops go to
      // their own table below.
      const routeRows = routes.map((r) => ({
        route_number: r.route_number, route_name: r.route_name,
        departure_times: r.departure_times,
        to_dsc_times: r.to_dsc_times ?? null,
        from_dsc_times: r.from_dsc_times ?? null,
        is_active: r.is_active,
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
      const keyFields = ["subject_code", "day_of_week", "start_time", "room_number", "batch", "section", "lab_subgroup", "department", "semester"]
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
// Building codes an occupied room token can start with, longest/most-specific
// first so e.g. "EMBEDLAB-KT-105" resolves to building "EMBEDLAB-KT" rather
// than a naive split("-")[0] cutting at the wrong hyphen ("EMBEDLAB").
const BUILDING_CODES = /^(EMBEDLAB-KT|IOT LAB-KT|KT|ANX\d{0,2}|G\d+|SH|CTBA)/
const LAB_BUILDING_CODES = ["EMBEDLAB-KT", "IOT LAB-KT"]

// Splits an already-isolated room token (e.g. "KT-208", "G1-011") into a
// clean building code + room number, instead of storing the whole token
// (with the building prefix still attached) as room_number the way this
// used to.
function splitRoom(room: string): { building: string; roomNumber: string } {
  const m = room.match(BUILDING_CODES)
  const building = m ? m[1] : room.split("-")[0]
  const roomNumber = room.slice(building.length).replace(/^-+/, "") || room
  return { building, roomNumber }
}

// Interprets an already-correctly-captured raw batch/section token pair
// (courseRegex's own capture groups, untouched) into the real signals a
// retake or lab-subgroup class needs — a post-processing step, not a
// regex-engine rewrite. "RE" batch + a section like "A(3C)" is a retake
// class (section letter + credit hours); a section like "J1"/"J2" on a
// normal batch is one half of a lab section split across two subgroups
// (each course/batch/section caps a lab at 25 seats, half of the 50-seat
// theory section).
function interpretBatchSection(rawBatch: string, rawSection: string): {
  batch: string; section: string; isRetake: boolean; labSubgroup: number | null; creditHours: number | null
} {
  if (/^RE$/i.test(rawBatch)) {
    const m = rawSection.match(/^([A-Za-z0-9]+)\(([0-9.]+)C?\)$/i)
    // schedule_slots.credit_hours is an INT column — round rather than
    // send a fractional value that would fail the insert outright (real
    // credit-hour values are conventionally whole numbers anyway; this is
    // just a safety net against an unusual PDF value).
    if (m) return { batch: rawBatch, section: m[1], isRetake: true, labSubgroup: null, creditHours: Math.round(parseFloat(m[2])) }
    return { batch: rawBatch, section: rawSection, isRetake: true, labSubgroup: null, creditHours: null }
  }
  const lab = rawSection.match(/^([A-Za-z])([12])$/)
  if (lab) return { batch: rawBatch, section: lab[1], isRetake: false, labSubgroup: parseInt(lab[2], 10), creditHours: null }
  return { batch: rawBatch, section: rawSection, isRetake: false, labSubgroup: null, creditHours: null }
}

// Strips the stray artifacts PDF/Excel extraction tends to leave behind
// (double spaces from column gaps, orphan punctuation, control characters)
// without touching legitimate characters in names — used on every
// extracted room/teacher/course/stop string so the UI shows clean,
// human-readable values instead of raw scrape noise.
function cleanName(s: string): string {
  let out = s.replace(/\s+/g, " ").trim()
  // Parens are excluded from the generic strip below and handled separately —
  // blindly stripping them there ate the real closing paren off identifiers
  // like room "KT-318(A)" or a retake section code "A(3C)" (confirmed against
  // a real routine PDF: every lettered sub-room and every retake section lost
  // its trailing ")"), since both legitimately end in one.
  out = out.replace(/^[\s\-_,.;:<>]+/, "").replace(/[\s\-_,.;:<>]+$/, "")
  const opens = (out.match(/\(/g) || []).length
  const closes = (out.match(/\)/g) || []).length
  if (closes > opens) out = out.replace(/\)+$/, "")
  if (opens > closes) out = out.replace(/^\(+/, "")
  return out.trim()
}

function parseClassRoutineLines(lines: string[]): any[] {
  const slots: any[] = []
  let currentDay: number | null = null
  let slotTimes: { start: string; end: string }[] = []
  const timeHeaderRegex = /(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})/g
  const courseRegex = /\b([A-Z]{2,6}\d{3})\(([A-Za-z0-9]+)_([A-Za-z0-9().]+?)\)\s+([A-Za-z_]{1,10})\b/g

  // Most rooms print their whole row (room repeated once per slot column,
  // with each occupied slot's course/teacher inline) on one physical PDF
  // line. Lab rooms (confirmed against a real routine PDF: KT-501(A/B),
  // KT-503/504/510/513, G1-001..G1-0NN — roughly two-thirds of the whole
  // routine by line count) instead print "<Room>" / "(COM LAB)" / optional
  // "<Course>(<batch>_<section>) <Teacher>" as 2-3 SEPARATE lines per slot,
  // so the single-line-per-row assumption silently dropped every one of
  // them. Buffer contiguous lines that share the same leading room token
  // and parse the joined result the same way a normal single-line row would
  // have been parsed — a normal row is just a buffer of length 1.
  let bufferLines: string[] = []
  let bufferToken: string | null = null
  // Captured from a "(COM LAB)"-style continuation line during buffering —
  // structurally recognized before this, but never stored anywhere.
  let bufferRoomTag: string | null = null
  const roomTagRegex = /^\(([A-Z][A-Z /]{1,20})\)$/

  function processRow(line: string) {
    // Was previously `line.split(new RegExp('(?=' + ROOM_START.source + ')'))`
    // — a lookahead-split finds EVERY position the pattern could match, not
    // just non-overlapping tokens, so a compound building code like
    // "EMBEDLAB-KT-105" got wrongly re-split a second time at its own
    // embedded "KT-105" substring (a bare "KT-<digits>" is also a valid
    // ROOM_START match on its own), shifting every course after it into the
    // wrong time-slot column. matchAll's implicit non-overlapping scan
    // (resumes after each match ends, not at the next possible start)
    // doesn't have this problem — confirmed against both a compound-code
    // room and a normal multi-room line in a standalone test harness.
    const roomMatches = [...line.matchAll(new RegExp(ROOM_START.source, "g"))]
    const chunks = roomMatches.length === 0 ? [line] : roomMatches.map((m, i) =>
      line.slice(m.index!, i + 1 < roomMatches.length ? roomMatches[i + 1].index! : line.length).trim())
    if (chunks.length === 0) return

    const roomMatch = chunks[0].match(ROOM_START)
    const room = cleanName(roomMatch ? roomMatch[0] : chunks[0].split(/\s+/)[0])
    const { building, roomNumber } = splitRoom(room)
    const roomType = bufferRoomTag
    const isLab = roomType !== null || LAB_BUILDING_CODES.includes(building)

    chunks.forEach((chunk, i) => {
      if (i >= slotTimes.length) return
      const matches = [...chunk.matchAll(courseRegex)]
      for (const m of matches) {
        const code = cleanName(m[1])
        const rawBatch = cleanName(m[2])
        const rawSection = cleanName(m[3])
        const teacher = cleanName(m[4])
        const { batch, section, isRetake, labSubgroup, creditHours } = interpretBatchSection(rawBatch, rawSection)
        slots.push({
          subject: code,
          subject_code: code,
          teacher_name: teacher,
          teacher_initial: teacher,
          room_number: roomNumber,
          building,
          room_type: roomType,
          is_lab: isLab,
          start_time: slotTimes[i].start + ":00",
          end_time: slotTimes[i].end + ":00",
          day_of_week: currentDay,
          credit_hours: creditHours ?? 3,
          department: "CSE",
          semester: 1,
          batch,
          section,
          is_retake: isRetake,
          lab_subgroup: labSubgroup,
          is_cancelled: false,
        })
      }
    })
  }

  function flush() {
    if (bufferLines.length === 0) return
    processRow(bufferLines.join(" "))
    bufferLines = []
    bufferToken = null
    bufferRoomTag = null
  }

  for (const rawLine of lines) {
    const line = rawLine.trim()
    if (!line) continue

    const dayMatch = Object.keys(DAY_NAMES).find((d) => new RegExp(`^${d}\\b`, "i").test(line))
    if (dayMatch) { flush(); currentDay = DAY_NAMES[dayMatch]; slotTimes = []; continue }

    if (/^room\s+course\s+teacher/i.test(line)) { flush(); continue }

    const timeMatches = [...line.matchAll(timeHeaderRegex)]
    if (timeMatches.length >= 4 && /^\d/.test(line)) {
      flush()
      slotTimes = timeMatches.map((m) => ({ start: m[1], end: m[2] }))
      continue
    }

    if (currentDay === null || slotTimes.length === 0) continue

    const roomMatch = line.match(ROOM_START)
    const startsWithRoom = roomMatch !== null && roomMatch.index === 0

    if (startsWithRoom) {
      const token = roomMatch![0]
      if (bufferToken === null) { bufferToken = token; bufferLines = [line] }
      else if (token === bufferToken) { bufferLines.push(line) }
      else { flush(); bufferToken = token; bufferLines = [line] }
    } else if (bufferToken !== null) {
      // Continuation text for the room currently being buffered — either the
      // "(COM LAB)" lab-tag label (captured into bufferRoomTag, not pushed
      // into the blob — it carries no course info) or a bare
      // "<Course>(<batch>_<section>) <Teacher>" line with no room token of
      // its own.
      const tagMatch = line.match(roomTagRegex)
      if (tagMatch) { bufferRoomTag = tagMatch[1]; continue }
      bufferLines.push(line)
    }
  }
  flush()
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
  // Deliberately doesn't require "Batch-" nearby anymore (see below) — only
  // the course code, optional title, and its own capacity bracket.
  const courseCapRegex = /\b([A-Z]{2,4}\d{3}):?\s*([\s\S]{0,80}?)\[(\d+)\]/g
  const batchRegex = /Batch-(\w+)/g
  const examType = /midterm|mid[\s-]?term/i.test(fullText) ? "mid" : "final"

  const dateMarkers = [...fullText.matchAll(dateRegex)].map((m) => ({
    index: m.index!,
    date: `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`,
  }))
  const slotMarkers = [...fullText.matchAll(slotTimeRegex)].map((m) => ({ index: m.index!, start: m[1] }))
  const batchMarkers = [...fullText.matchAll(batchRegex)].map((m) => ({ index: m.index!, end: m.index! + m[0].length, batch: m[1] }))

  const nearestBefore = <T extends { index: number }>(markers: T[], idx: number): T | null => {
    let best: T | null = null
    for (const m of markers) { if (m.index <= idx) best = m; else break }
    return best
  }
  const nearestAfter = <T extends { index: number }>(markers: T[], idx: number): T | null =>
    markers.find((m) => m.index >= idx) ?? null

  const seenSinceDate = new Map<number, number>()
  // The real source (confirmed against an actual mid-term routine PDF)
  // prints each day's own "Slot A/B/C: <time>" header BEFORE that day's
  // date line, not after — a slot-time header only ever changes between
  // days (a Saturday makeup session had different times than the regular
  // weekdays), so getting the direction backwards silently gave one day's
  // courses the WRONG following day's slot times, and left the final day's
  // courses with no time at all (no header follows the last date). Slot
  // markers for a date are therefore the ones between the PREVIOUS date and
  // this one; if none exist (a date repeated to spill onto a second table
  // block with no header of its own), fall back to the last real header
  // seen rather than leaving start_time null.
  let lastKnownSlots: { index: number; start: string }[] = []
  for (const m of fullText.matchAll(courseCapRegex)) {
    const idx = m.index!
    const endIdx = idx + m[0].length
    const [, code, title] = m

    const dateMarker = nearestBefore(dateMarkers, idx)
    if (!dateMarker) continue

    // A course's batch is whichever "Batch-XX" marker comes next after its
    // own capacity bracket — several elective courses commonly share ONE
    // trailing Batch- marker (e.g. 4 electives offered to the same batch in
    // one slot), and requiring Batch- to sit immediately after each course's
    // own bracket (the old approach) meant only the LAST of those courses
    // ever matched at all; the other 3 silently vanished.
    const batchMarker = nearestAfter(batchMarkers, endIdx)
    if (!batchMarker) continue
    const nextDate = dateMarkers.find((d) => d.index > dateMarker.index)
    if (nextDate && batchMarker.index > nextDate.index) continue // batch marker belongs to a later day — reject rather than mis-assign

    const dIdx = dateMarkers.findIndex((d) => d.index === dateMarker.index)
    const prevBound = dIdx > 0 ? dateMarkers[dIdx - 1].index : -1
    let slotsForDay = slotMarkers.filter((s) => s.index > prevBound && s.index < dateMarker.index)
    if (slotsForDay.length === 0) slotsForDay = lastKnownSlots
    else lastKnownSlots = slotsForDay

    const seen = seenSinceDate.get(dateMarker.index) ?? 0
    const slot = slotsForDay.length > 0 ? slotsForDay[seen % slotsForDay.length] : null
    seenSinceDate.set(dateMarker.index, seen + 1)

    exams.push({
      subject: cleanName(title) || code,
      subject_code: cleanName(code),
      exam_date: dateMarker.date,
      start_time: slot ? slot.start + ":00" : null,
      end_time: null,
      exam_type: examType,
      batch: cleanName(batchMarker.batch),
      department: "CSE",
      is_retake: /^RE/i.test(batchMarker.batch),
    })
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
  // A PDF export of the transport sheet (confirmed against a real "Transport
  // Schedule ... .xlsx exported to PDF" file) lands every table cell on its
  // own physical text line — route number, start time, route name, the full
  // stop list, and each departure time are all separate single-cell rows.
  // Neither Shape A below (needs real multi-column rows) nor the old
  // same-line blob scrape (needed a whole route packed onto one line, and
  // only recognized plain-digit route numbers, never this sheet's "R1"/"F4"
  // style) can ever match that shape — hand off to a parser built for it
  // before falling through to logic that structurally cannot apply.
  if (rows.length > 0 && rows.every((r) => r.length <= 1)) {
    const flatLines = rows.map((r) => r[0] ?? "").filter((l) => l.trim())
    const flattenedRoutes = parseTransportLinesFlattened(flatLines)
    if (flattenedRoutes.length > 0) return flattenedRoutes
  }

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

// Line-flattened transport PDF (see the comment at the top of
// parseTransportRows): route boundaries are found by looking for a line
// that STARTS with a route token ("R1".."R15", "F1".."F4" in the real
// sheet), then every line up to the next such token is one route's block,
// however many lines its fields happened to spread across.
const TRANSPORT_BOILERPLATE = [
  /^Daffodil International University$/i, /^Transport Schedule for/i,
  /^Route$/i, /^No$/i, /^Start Time$/i, /^\(To DSC\)$/i, /^Route Name Route Details$/i,
  /^Departure Time$/i, /^\(From DSC\)$/i, /^Shuttle service$/i, /^Friday Schedule @ DSC$/i,
]
const ROUTE_TOKEN = /^([RF]\d{0,2})\b/

function normalizeTransportTime(raw: string): string | null {
  // The source uses both "10:50 AM" and "10.50 AM" (a period instead of a
  // colon) and both "1:30 PM" and "1:30:00 PM" — normalize to one form so
  // dedup and display are consistent.
  const m = raw.match(/(\d{1,2})[:.](\d{2})(?::\d{2})?\s*(AM|PM|am|pm)/)
  if (!m) return null
  return `${parseInt(m[1], 10)}:${m[2]} ${m[3].toUpperCase()}`
}

function parseTransportLinesFlattened(lines: string[]): any[] {
  const clean = lines.filter((l) => !TRANSPORT_BOILERPLATE.some((p) => p.test(l.trim())))
  const blocks: { token: string; lines: string[] }[] = []
  let current: { token: string; lines: string[] } | null = null
  for (const raw of clean) {
    const line = raw.trim()
    if (!line) continue
    const m = line.match(ROUTE_TOKEN)
    if (m) {
      if (current) blocks.push(current)
      current = { token: m[1], lines: [line] }
    } else if (current) {
      current.lines.push(line)
    }
  }
  if (current) blocks.push(current)

  const routes: any[] = []
  const lastNumeric: Record<string, number> = { R: 0, F: 0 }
  for (const block of blocks) {
    let routeNumber = block.token
    const prefix = routeNumber[0]
    const numMatch = routeNumber.match(/\d+/)
    if (numMatch) {
      lastNumeric[prefix] = parseInt(numMatch[0], 10)
    } else {
      // A bare "R"/"F" with no digit is a real extraction glitch seen in the
      // live document (one route printed as just "R") — infer the next
      // sequential number for that prefix rather than dropping the route.
      lastNumeric[prefix] = (lastNumeric[prefix] ?? 0) + 1
      routeNumber = `${prefix}${lastNumeric[prefix]}`
    }

    const blob = block.lines.join(" ")
    const timeMatches = [...blob.matchAll(/\d{1,2}[:.]\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)/g)]
      .map((m) => normalizeTransportTime(m[0])).filter((t): t is string => t !== null)
    const uniqTimes = [...new Set(timeMatches)]
    const toDscTimes = uniqTimes.slice(0, 1)
    const fromDscTimes = uniqTimes.slice(1)

    // Every "<>"/">"-delimited segment is a candidate stop list; the source
    // always prints the full stop-by-stop route_details as the LONGEST such
    // segment and a short route_name summary as a shorter one. "&" is
    // included since real stop names use it ("C&B"); a trailing run of
    // digits/AM-PM is stripped since with no separator after the last stop
    // the match otherwise keeps eating into the adjacent departure-time text
    // that follows it in the blob (confirmed against the real sheet: "...
    // Daffodil Smart City 10.50 AM 9" swallowing the next line's "9:40 AM").
    const segRegex = /[A-Za-z][A-Za-z0-9 .'&\-]*(?:\s*[<>]+\s*[A-Za-z][A-Za-z0-9 .'&\-]*)+/g
    const segments = [...blob.matchAll(segRegex)]
      .map((m) => m[0].replace(/\s+\d{1,2}[:.]\d{1,2}.*$/, ""))
    const toStops = (seg: string) => seg.split(/<>|>|</).map((s) => cleanName(s)).filter(Boolean)
      .filter((name, i, arr) => i === 0 || name !== arr[i - 1])
      // A stray "AM"/"PM" or bare 1-2 digit number is leftover from a time
      // string the segment regex brushed up against (e.g. it resumes right
      // after "7:00 " on one side of a colon, or stops right before "10:50"
      // on the other) — never a real stop name on its own.
      .filter((name) => !/^(AM|PM)$/i.test(name) && !/^\d{1,2}$/.test(name))
    const segStops = segments.map(toStops).filter((s) => s.length >= 2)
    segStops.sort((a, b) => b.length - a.length)
    // The short "route name" summary line and the long stop-by-stop route
    // details usually merge into one contiguous match anyway (nothing but a
    // space separates them in the blob), so deriving the name from the
    // resolved stop list's own endpoints is more reliable than trying to
    // separately pick out a second, shorter segment as "the name".
    const stops: string[] = segStops[0] ?? []
    if (stops.length > 0) {
      // The route's start time ("7:00 AM") immediately precedes the first
      // stop with nothing but a space between them, so the leading "AM"/"PM"
      // merges into that first stop's own text instead of being its own
      // splittable token; likewise the arrival time's leading digits ("10"
      // of "10:50 AM") stick onto the last stop, the campus itself.
      stops[0] = stops[0].replace(/^(AM|PM)\s+/i, "").trim()
      stops[stops.length - 1] = stops[stops.length - 1].replace(/\.?\s*\d{1,2}$/, "").trim()
    }
    const routeName = stops.length ? `${stops[0]} - ${stops[stops.length - 1]}` : routeNumber

    routes.push({
      route_number: routeNumber, route_name: cleanName(routeName),
      to_dsc_times: toDscTimes, from_dsc_times: fromDscTimes,
      departure_times: fromDscTimes.length ? fromDscTimes : toDscTimes,
      stops: stops.map((name) => ({ name, time: null })),
      is_active: true,
    })
  }
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
