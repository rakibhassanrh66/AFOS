import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import * as XLSX from "https://esm.sh/xlsx@0.18.5"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!

// Server-side upload bounds. Even though callers are already restricted to
// upload-authorized roles, the client is not trusted to have enforced size
// limits — a hand-crafted request could otherwise ship an arbitrarily large
// Excel file or `lines` array and exhaust the function's compute budget.
// A full department routine is ~600-900 rows and well under 1MB, so these
// caps are generous headroom, not a real-world constraint.
const MAX_EXCEL_BYTES = 15 * 1024 * 1024   // 15 MB
const MAX_LINES = 20000

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
    const { data: callerProfile } = await supabase.from("profiles").select("role, department").eq("id", authData.user.id).maybeSingle()
    if (!callerProfile) {
      return new Response(JSON.stringify({ error: "No profile found for caller." }), { status: 403, headers: corsHeaders })
    }
    // Capability authorization is deferred until `type` is known (below),
    // since routine / exam_seat / transport uploads require different
    // capabilities. Legacy admin/dept_admin/teacher roles keep full upload
    // access; delegated grantees are restricted to exactly what they hold.

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
    let requestedDepartment: string | null = null

    if (contentType.includes("application/json")) {
      const body = await req.json()
      type = (body.type || "schedule").toLowerCase()
      if (Array.isArray(body.lines) && body.lines.length > MAX_LINES) {
        return new Response(JSON.stringify({ error: `Too many lines (max ${MAX_LINES}).` }), { status: 413, headers: corsHeaders })
      }
      lines = Array.isArray(body.lines) ? body.lines.map((l: unknown) => String(l).trim()).filter(Boolean) : []
      rows = lines.map((l) => [l])
      requestedDepartment = typeof body.department === "string" && body.department.trim() ? body.department.trim() : null
    } else {
      const formData = await req.formData()
      const file = formData.get("file") as File
      type = ((formData.get("type") as string) || "schedule").toLowerCase()
      if (!file) return new Response(JSON.stringify({ error: "No file provided" }), { status: 400, headers: corsHeaders })
      if (!/\.(xlsx|xls)$/i.test(file.name)) {
        return new Response(JSON.stringify({ error: "This endpoint only accepts Excel files directly. PDFs must be sent as extracted text (the app does this automatically)." }), { status: 400, headers: corsHeaders })
      }
      if (file.size > MAX_EXCEL_BYTES) {
        return new Response(JSON.stringify({ error: `File too large (max ${MAX_EXCEL_BYTES / (1024 * 1024)} MB).` }), { status: 413, headers: corsHeaders })
      }
      rows = await extractRowsFromExcel(file)
      lines = rows.map((r) => r.join(" "))
      const formDept = formData.get("department")
      requestedDepartment = typeof formDept === "string" && formDept.trim() ? formDept.trim() : null
    }

    // This used to hardcode "CSE" for every upload regardless of who
    // uploaded it or what the file actually contained. Only super_admin can
    // override which department an upload gets tagged as (the app's own
    // dropdown is super_admin-only) — every other authorized role
    // (admin/dept_admin/teacher) is locked to their OWN profile department
    // server-side regardless of what a client sends, so a compromised or
    // hand-crafted request from a non-super_admin account can't mislabel
    // another department's routine either. "CSE" is only the very last
    // resort, for an account with no department set at all.
    const uploadDepartment =
      (callerProfile.role === "super_admin" && requestedDepartment) ||
      callerProfile.department || "CSE"

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

      // Was previously one DELETE round-trip per obsolete row -- fine for a
      // handful of stale rows, but a re-upload that changes the identity-key
      // format itself (e.g. this session's room_number split, or adding
      // lab_subgroup to the key) makes nearly every pre-existing row look
      // "obsolete" under the new key at once. Confirmed live: a real
      // ~1900-row class-routine re-upload under the old row-by-row loop blew
      // straight through the edge function's time budget (HTTP 504) well
      // before finishing. Fetching `id` alongside the key fields lets the
      // actual deletes happen in large batched `.in('id', ...)` calls instead.
      // PostgREST caps a single response at 1000 rows by default — a plain
      // unpaginated .select() here silently only ever saw the FIRST 1000 of
      // a department's existing rows, so any table already past that size
      // left every row beyond it permanently un-inspected (never flagged
      // obsolete, never deleted) on every future upload. Confirmed live: a
      // real re-upload against 4249 pre-existing CSE rows only removed a
      // fraction of the true stale set and the table grew to 5516 instead of
      // shrinking to the new file's real ~1854 rows. Page through with
      // .range() until a short page confirms there's nothing left, so this
      // holds regardless of how large a department's routine ever grows.
      let deleted = 0
      for (const combo of scopeCombos.values()) {
        const existing: any[] = []
        const pageSize = 1000
        for (let from = 0; ; from += pageSize) {
          let query = supabase.from(table).select(["id", ...keyFields].join(",")).range(from, from + pageSize - 1)
          for (const f of scopeFields) query = query.eq(f, combo[f])
          const { data: page, error } = await query
          if (error || !page) break
          existing.push(...page)
          if (page.length < pageSize) break
        }
        const obsoleteIds = existing.filter((row) => !newKeys.has(keyOf(row))).map((row) => row.id)
        for (let i = 0; i < obsoleteIds.length; i += 500) {
          const idBatch = obsoleteIds.slice(i, i + 500)
          const { error: delErr, count } = await supabase.from(table).delete({ count: "exact" }).in("id", idBatch)
          if (!delErr) deleted += count ?? idBatch.length
          else if (batchErrors.length < 3) batchErrors.push(delErr.message)
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

    // The PDF prints its own header metadata above the first day section
    // (confirmed against a real routine: "Class Routine for CSE Program" /
    // "Version V5" / "Effective From: Saturday 11 July, 2026 Prepared by:
    // Class Routine Committee, Dept. of CSE") — schedule_slots/exams only
    // ever held per-session rows, nowhere captured this, so the app header
    // had no real data to show. One row per (department, routine_type);
    // a re-upload overwrites the previous header the same way it replaces
    // the underlying rows. Best-effort only — silently no-ops if the text
    // isn't found rather than failing the whole upload over cosmetic data.
    async function upsertRoutineHeaderMeta(department: string, routineType: string) {
      const meta = extractRoutineHeaderMeta(lines)
      if (!meta.versionLabel && !meta.effectiveFromText && !meta.preparedBy) return
      await supabase.from("routine_uploads").upsert({
        department, routine_type: routineType,
        version_label: meta.versionLabel, effective_from_text: meta.effectiveFromText, prepared_by: meta.preparedBy,
        uploaded_by: authData.user.id, uploaded_at: new Date().toISOString(),
      }, { onConflict: "department,routine_type" })
    }

    if (type === "class_routine") {
      const slots = parseClassRoutineLines(lines, uploadDepartment)
      if (slots.length === 0) {
        return new Response(JSON.stringify({ error: "No class routine sessions recognized in file.", linesPreview: lines.slice(0, 5) }), { status: 400, headers: corsHeaders })
      }
      await upsertRoutineHeaderMeta(uploadDepartment, "class_routine")
      const keyFields = ["subject_code", "day_of_week", "start_time", "room_number", "batch", "section", "lab_subgroup", "department", "semester"]
      const inserted = await batchUpsert("schedule_slots", slots, keyFields.join(","))
      // Scoped by department alone, not department+semester -- one
      // class-routine file is a full snapshot of the WHOLE department across
      // every real batch/semester at once (semester is no longer a single
      // hardcoded value per upload), so replacing "everything in this
      // department not present in the new file" needs exactly one scope,
      // not one query per distinct semester value.
      const removed = await deleteObsolete("schedule_slots", slots, keyFields, ["department"])
      const dept = slots[0]?.department
      // A whole-department upload spans many real batches/semesters at
      // once (not the single semester this used to hardcode-assume), so
      // resolve notification recipients per distinct real batch -- the
      // same field watchMyClassesAsStudent actually matches students by --
      // rather than by profiles.semester, which was already a separate,
      // independently-set field that only ever matched the one hardcoded
      // semester value and silently missed every other batch in the upload.
      const distinctBatches = [...new Set(slots.map((s: any) => s.batch).filter((b: string) => !/^RE$/i.test(b)))]
      const classUserIdSets = await Promise.all(distinctBatches.map((b) => resolveUserIdsByBatch(b)))
      const classUserIds = [...new Set(classUserIdSets.flat())]
      await notifyUsers(classUserIds, "Class routine updated",
        `Your ${dept ?? ""} class routine has been updated.`, "/schedule")
      return new Response(JSON.stringify({ success: true, slotsInserted: inserted, slotsRemoved: removed, totalParsed: slots.length, type: "class_routine", batchErrors }), { headers: corsHeaders })
    }

    if (type === "exam_routine") {
      const exams = parseExamRoutineLines(lines, uploadDepartment)
      if (exams.length === 0) {
        return new Response(JSON.stringify({ error: "No exam routine entries recognized in file.", linesPreview: lines.slice(0, 5) }), { status: 400, headers: corsHeaders })
      }
      await upsertRoutineHeaderMeta(uploadDepartment, "exam_routine")
      // start_time deliberately excluded from the key (matches the
      // exams_identity index) -- a subject sits exactly one exam per
      // (date, batch, exam_type), so keying on start_time too meant a
      // later upload that corrected a previously-unparsed start_time
      // inserted a second row instead of updating the first. Confirmed
      // live and cleaned up in 20260712180000_fix_exams_identity_key.sql.
      const keyFields = ["subject_code", "exam_date", "batch", "exam_type"]
      const inserted = await batchUpsert("exams", exams, keyFields.join(","))
      const removed = await deleteObsolete("exams", exams, keyFields, ["batch", "exam_type"])
      const batch = exams[0]?.batch
      const examUserIds = await resolveUserIdsByBatch(batch)
      await notifyUsers(examUserIds, "Exam routine updated",
        `Your ${exams[0]?.exam_type === "mid" ? "midterm" : "final"} exam routine has been updated.`, "/schedule")
      return new Response(JSON.stringify({ success: true, slotsInserted: inserted, slotsRemoved: removed, totalParsed: exams.length, type: "exam_routine", batchErrors }), { headers: corsHeaders })
    }

    const slots = parseScheduleRows(rows, uploadDepartment)
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


function parseScheduleRows(rows: string[][], department: string): any[] {
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
      start_time: to24Hour(times[i].start) + ':00',
      end_time: to24Hour(times[i].end) + ':00',
      day_of_week: dayNum,
      credit_hours: 3,
      department,
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

// The routine's own time-slot header prints in bare 12-hour style with NO
// am/pm marker at all ("08:30-10:00 10:00-11:30 11:30-01:00 01:00-02:30
// 02:30-04:00 04:00-05:30") — confirmed against a real routine PDF. Stored
// literally, "01:00" et al land at 1 AM instead of 1 PM, so every afternoon
// class (three of the six daily slots) sorted BEFORE the actual morning
// ones once real students' schedules were checked live. DIU's whole
// teaching day runs 08:30 AM–05:30 PM, one unbroken stretch with no
// classes before 8 or after 7 — so within that specific known range, an
// hour of 1–7 is unambiguously PM and 8–11 is unambiguously AM; no
// sequential/stateful crossover tracking is needed.
function to24Hour(hhmm: string): string {
  const [h, m] = hhmm.split(":")
  const hour = parseInt(h, 10)
  const hour24 = hour >= 1 && hour <= 7 ? hour + 12 : hour
  return `${String(hour24).padStart(2, "0")}:${m}`
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
// class (section letter + credit hours); a section like "J1"/"J2" is one
// half of a lab section split across two subgroups (each course/batch/
// section caps a lab at 25 seats, half of the 50-seat theory section) —
// and a retake course can ALSO be lab-split this way (e.g.
// "CSE124(RE_A1(1.5C))" paired with "CSE124(RE_A2(1.5C))"), confirmed
// against a real routine PDF, so the subgroup check applies either way.
function interpretBatchSection(rawBatch: string, rawSection: string): {
  batch: string; section: string; isRetake: boolean; labSubgroup: number | null; creditHours: number | null
} {
  const isRetake = /^RE$/i.test(rawBatch)
  let section = rawSection
  let creditHours: number | null = null
  if (isRetake) {
    // A rare handful of rows carry an extra 2-letter annotation tag after
    // the credit-hours group whose meaning isn't confirmed from available
    // data (e.g. "A(3C)(CN)", "A(3C)(CD)") -- strip it first (only when
    // what's left still looks like it has its own credit-hours group) so
    // the real section/credit-hours still parse cleanly instead of the
    // whole thing getting stuck as one unparsed string.
    const annotated = section.match(/^(.+)\([A-Z]{2}\)$/)
    if (annotated && /\(\d/.test(annotated[1])) section = annotated[1]
    // schedule_slots.credit_hours is an INT column -- round rather than
    // send a fractional value that would fail the insert outright (real
    // credit-hour values are conventionally whole numbers anyway; this is
    // just a safety net against an unusual PDF value). Tolerates a stray
    // trailing period after "C" ("3C.") seen in several real rows.
    const creditMatch = section.match(/^(.+)\(([0-9]+(?:\.[0-9]+)?)C?\.?\)$/i)
    if (creditMatch) {
      section = creditMatch[1]
      creditHours = Math.round(parseFloat(creditMatch[2]))
    }
  }
  const lab = section.match(/^([A-Za-z])([12])$/)
  if (lab) return { batch: rawBatch, section: lab[1], isRetake, labSubgroup: parseInt(lab[2], 10), creditHours }
  return { batch: rawBatch, section, isRetake, labSubgroup: null, creditHours }
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

// Scans only the lines BEFORE the first day-section header (SATURDAY, ...)
// for the PDF's own printed header metadata — restricting the scan avoids
// ever matching similar-looking text buried deeper in the actual grid.
function extractRoutineHeaderMeta(lines: string[]): { versionLabel: string | null; effectiveFromText: string | null; preparedBy: string | null } {
  const dayHeaderIdx = lines.findIndex((l) => Object.keys(DAY_NAMES).some((d) => new RegExp(`^${d}\\b`, "i").test(l.trim())))
  const headerText = (dayHeaderIdx === -1 ? lines.slice(0, 10) : lines.slice(0, dayHeaderIdx)).join(" ")

  const versionMatch = headerText.match(/version\s*([A-Za-z0-9.]+)/i)
  const effFromMatch = headerText.match(/effective\s+from\s*:?\s*(.+?)(?:\s+prepared\s+by\s*:|\s*$)/i)
  const preparedByMatch = headerText.match(/prepared\s+by\s*:?\s*(.+)$/i)

  return {
    versionLabel: versionMatch ? versionMatch[1].trim() : null,
    effectiveFromText: effFromMatch ? effFromMatch[1].trim() : null,
    preparedBy: preparedByMatch ? preparedByMatch[1].trim() : null,
  }
}

function parseClassRoutineLines(lines: string[], department: string): any[] {
  const slots: any[] = []
  let currentDay: number | null = null
  let slotTimes: { start: string; end: string }[] = []
  // A day-name word a PDF text run split across two physical lines (e.g.
  // "THURSDAY" extracted as "THURSDA" then "Y" — confirmed against a real
  // routine PDF), held until the next line either completes it or proves it
  // wasn't a day name after all.
  let pendingDayFragment: string | null = null
  // Confirmed against a real routine PDF: 3 of the week's 5 day transitions
  // (Sat->Sun, Sun->Mon, Tue->Wed) print NO day-header text at all before
  // the next day's rooms start — the new day's whole room list just
  // silently continues right after the previous day's, reusing the same
  // slot-time columns, with the literal day name (when present at all)
  // landing well after that data instead of before it. A room token
  // reappearing (not just contiguing with itself) is the only reliable
  // signal available to catch these — every room in a day's table is only
  // ever listed once, so seeing one again means a new day has begun.
  let seenRoomsThisDay = new Set<string>()
  const timeHeaderRegex = /(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})/g
  // Teacher-initial group now allows digits/underscore ("NT_2", "EEE_11" —
  // confirmed against a real routine PDF: several specialist retake
  // instructors are tagged this way) and tolerates zero space before the
  // teacher initial (some extractions show none), where the original
  // letters-only group + required space silently dropped the whole course
  // match for any such row.
  const courseRegex = /\b([A-Z]{2,6}\d{3})\(([A-Za-z0-9]+)_([A-Za-z0-9().]+?)\)\s*([A-Za-z0-9_]{1,10})\b/g

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
  // Captured from a room's parenthetical tag line(s) during buffering --
  // structurally recognized before this, but never stored anywhere. Not
  // just short all-caps tags like "(COM LAB)" -- some rooms (KT-809/810/
  // 815/816, SH-103/105) carry a full descriptive tag that wraps across
  // several physical lines, e.g. "(Electrical" / "Circuits Lab and" /
  // "Digital" / "Electronics Lab)" (confirmed against a real routine PDF).
  let bufferRoomTag: string | null = null
  let inRoomTagBlock = false
  let roomTagAccum: string[] = []

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
        // A rare handful of source rows have a genuinely malformed course
        // tag with a missing closing paren and no teacher printed at all
        // (confirmed in a real routine PDF: room ANX1-103's
        // "CSE426(RE_A(3C) ANX1-103" — note the single, not double, closing
        // paren) — the unbalanced parens make the regex's teacher-initial
        // group swallow the START of the NEXT room's token instead ("ANX1")
        // rather than leaving it unmatched. A real teacher initial in this
        // dataset is never immediately followed by "-" (only a room token
        // is, e.g. "KT-208"/"ANX1-103"), so that combination — looks like a
        // room-token prefix AND is glued directly to a hyphen — means this
        // capture is misattributed room text, not a real teacher; leave it
        // blank rather than show a wrong name.
        const teacherRaw = m[4]
        const misattributedRoomToken =
          chunk[m.index! + m[0].length] === "-" && /^[A-Z]{1,6}\d{0,4}$/.test(teacherRaw)
        const teacher = misattributedRoomToken ? "" : cleanName(teacherRaw)
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
          department,
          batch,
          section,
          is_retake: isRetake,
          // schedule_slots.lab_subgroup is NOT NULL — 0 is the real "not a
          // lab subgroup" sentinel (see the schema migration), so the
          // unique index used by this upsert's ON CONFLICT can actually
          // detect a conflict for non-lab rows instead of every one of them
          // silently bypassing it (NULL is never equal to NULL in Postgres).
          lab_subgroup: labSubgroup ?? 0,
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
    inRoomTagBlock = false
    roomTagAccum = []
  }

  // Applies an explicitly-matched day name (whether read whole or
  // reassembled from a split fragment). Deliberately does NOT reset
  // seenRoomsThisDay when the matched day is the SAME value currentDay
  // already holds — confirmed against a real routine PDF: the literal
  // "SUNDAY" header text lands mid-sequence, partway through Sunday's OWN
  // room list (KT-201..KT-515 print before the header, KT-516..ANX1-210
  // after it — one continuous day's table, not two). Unconditionally wiping
  // the seen-room set on every explicit header match — even one that isn't
  // actually changing the day — erased the record that KT-201..KT-515
  // already belonged to today, so those rooms' real SECOND appearance later
  // in the file (genuinely the next day, once the room list naturally
  // repeats) went undetected and got misattributed back to Sunday instead
  // of rolling over.
  function applyExplicitDay(day: number) {
    flush()
    if (day !== currentDay) seenRoomsThisDay = new Set()
    currentDay = day
    slotTimes = []
  }

  for (const rawLine of lines) {
    const line = rawLine.trim()
    if (!line) continue

    if (pendingDayFragment !== null) {
      const combined = pendingDayFragment + line
      const combinedMatch = Object.keys(DAY_NAMES).find((d) => new RegExp(`^${d}\\b`, "i").test(combined))
      pendingDayFragment = null
      if (combinedMatch) { applyExplicitDay(DAY_NAMES[combinedMatch]); continue }
      // Wasn't actually a split day name after all — fall through and
      // re-check this line normally below (the held fragment is dropped;
      // it wasn't meaningful content on its own either way).
    }

    const dayMatch = Object.keys(DAY_NAMES).find((d) => new RegExp(`^${d}\\b`, "i").test(line))
    if (dayMatch) { applyExplicitDay(DAY_NAMES[dayMatch]); continue }

    if (/^[A-Za-z]{3,8}$/.test(line) &&
        Object.keys(DAY_NAMES).some((d) => d.startsWith(line.toLowerCase()) && d !== line.toLowerCase())) {
      pendingDayFragment = line
      continue
    }

    if (/^room\s+course\s+teacher/i.test(line)) { flush(); continue }

    const timeMatches = [...line.matchAll(timeHeaderRegex)]
    if (timeMatches.length >= 4 && /^\d/.test(line)) {
      flush()
      slotTimes = timeMatches.map((m) => ({ start: to24Hour(m[1]), end: to24Hour(m[2]) }))
      continue
    }

    if (currentDay === null || slotTimes.length === 0) continue

    const roomMatch = line.match(ROOM_START)
    const startsWithRoom = roomMatch !== null && roomMatch.index === 0

    if (startsWithRoom) {
      const token = roomMatch![0]
      if (token === bufferToken) {
        bufferLines.push(line)
      } else {
        flush()
        // Deliberately NOT special-cased on "is bufferToken null" (i.e. "is
        // this the very first room ever") — bufferToken also goes back to
        // null on an UNRELATED flush, e.g. the "Room Course Teacher" column
        // header re-printing mid-document right at one of these hidden day
        // boundaries (confirmed against a real routine PDF). A special case
        // there would let exactly the first room of the new day silently
        // skip this check and roll over one room too late, misattributing
        // that one room's whole row to the previous day. seenRoomsThisDay
        // starts empty at a genuine day start either way, so this check
        // alone is already correct for the true first room too — no bypass
        // needed.
        if (seenRoomsThisDay.has(token)) {
          currentDay = currentDay === null ? 0 : currentDay + 1
          seenRoomsThisDay = new Set()
        }
        seenRoomsThisDay.add(token)
        bufferToken = token
        bufferLines = [line]
      }
    } else if (bufferToken !== null) {
      // Continuation text for the room currently being buffered — either a
      // parenthetical room-type tag (captured into bufferRoomTag, not pushed
      // into the blob — it carries no course info; may span several lines
      // for the longer descriptive tags) or a bare
      // "<Course>(<batch>_<section>) <Teacher>" line with no room token of
      // its own.
      if (inRoomTagBlock) {
        roomTagAccum.push(line)
        if (line.endsWith(")")) {
          bufferRoomTag = roomTagAccum.join(" ").replace(/^\(/, "").replace(/\)$/, "").trim()
          inRoomTagBlock = false
          roomTagAccum = []
        }
        continue
      }
      if (line.startsWith("(")) {
        if (line.endsWith(")")) {
          bufferRoomTag = line.slice(1, -1).trim()
        } else {
          inRoomTagBlock = true
          roomTagAccum = [line]
        }
        continue
      }
      bufferLines.push(line)
    }
  }
  flush()

  // schedule_slots.semester is NOT NULL, but a whole-department routine
  // upload spans many different real semesters (one per batch), not one
  // fixed value -- self-calibrate from the batches actually present in
  // THIS upload rather than a hardcoded constant that would go stale every
  // term: DIU's batch numbers increment by 1 each trimester and the newest
  // batch is always semester 1, so semester = (highest batch here) - batch
  // + 1. Confirmed against a real routine's own exam-routine cross-reference
  // (batch 72 = semester 1 down to batch 64 = semester 9). Retake rows
  // ("RE" batch) have no single real semester -- 0 is a sentinel, never a
  // real value, and retake lookup happens by course-code search, not by
  // semester filtering, so it's never used for matching.
  const numericBatches = slots.map((s) => parseInt(s.batch, 10)).filter((n) => !Number.isNaN(n))
  const maxBatch = numericBatches.length ? Math.max(...numericBatches) : null
  for (const s of slots) {
    const b = parseInt(s.batch, 10)
    s.semester = !Number.isNaN(b) && maxBatch !== null ? maxBatch - b + 1 : 0
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
function parseExamRoutineLines(lines: string[], department: string): any[] {
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
  // Same bare-hour-with-no-marker issue as the class routine's own header
  // (see to24Hour's comment) — exam slots print in business hours too, so
  // the same 1–7-is-PM / 8–11-is-AM rule applies regardless of whether an
  // am/pm word happens to be present in this particular slot's text.
  const slotMarkers = [...fullText.matchAll(slotTimeRegex)].map((m) => ({ index: m.index!, start: to24Hour(m[1]) }))
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
      department,
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
  const usedRouteNumbers = new Set<string>()
  for (const block of blocks) {
    let routeNumber = block.token
    const prefix = routeNumber[0]
    const numMatch = routeNumber.match(/\d+/)
    if (numMatch) {
      lastNumeric[prefix] = Math.max(lastNumeric[prefix] ?? 0, parseInt(numMatch[0], 10))
    }
    if (!numMatch || usedRouteNumbers.has(routeNumber)) {
      // A bare "R"/"F" with no digit is a real extraction glitch seen in the
      // live document (one route printed as just "R") — infer the next
      // sequential number for that prefix rather than dropping the route.
      // The same fallback also covers a genuine source-sheet typo (confirmed
      // against a real transport schedule: the Friday shuttle section lists
      // two entirely different routes both labeled "F4") — reusing an
      // already-claimed number would otherwise silently drop one whole real
      // route when the upsert's route_number conflict key collides.
      lastNumeric[prefix] = (lastNumeric[prefix] ?? 0) + 1
      routeNumber = `${prefix}${lastNumeric[prefix]}`
    }
    usedRouteNumbers.add(routeNumber)

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
