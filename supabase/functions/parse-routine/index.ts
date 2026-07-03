import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import * as XLSX from "https://esm.sh/xlsx@0.18.5"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const formData = await req.formData()
    const file = formData.get("file") as File
    // 'type' selects which structured table the parsed rows go into:
    //   'schedule'  (default) -> schedule_slots
    //   'transport'            -> transport_routes
    const type = ((formData.get("type") as string) || "schedule").toLowerCase()
    if (!file) return new Response(JSON.stringify({ error: "No file provided" }), { status: 400, headers: corsHeaders })

    const isExcel = /\.(xlsx|xls)$/i.test(file.name)
    const rows: string[][] = isExcel ? await extractRowsFromExcel(file) : await extractRowsFromPDF(file)

    if (rows.length === 0) {
      return new Response(JSON.stringify({ error: "Could not extract any rows from the file. For PDFs, ensure it is text-based, not scanned; for Excel, ensure the first sheet has the data." }), { status: 400, headers: corsHeaders })
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)

    if (type === "transport") {
      const routes = parseTransportRows(rows)
      if (routes.length === 0) {
        return new Response(JSON.stringify({ error: "No transport routes recognized in file." }), { status: 400, headers: corsHeaders })
      }
      let inserted = 0
      for (const route of routes) {
        const { error } = await supabase.from("transport_routes").upsert(route, { onConflict: "route_number" })
        if (!error) inserted++
      }
      return new Response(JSON.stringify({ success: true, slotsInserted: inserted, totalParsed: routes.length, type: "transport" }), { headers: corsHeaders })
    }

    const slots = parseScheduleRows(rows)
    if (slots.length < 3) {
      return new Response(JSON.stringify({ error: "Routine format not recognized. Found fewer than 3 slots.", rowsPreview: rows.slice(0, 5) }), { status: 400, headers: corsHeaders })
    }
    let inserted = 0
    for (const slot of slots) {
      const { error } = await supabase.from("schedule_slots").upsert(slot, {
        onConflict: "subject_code,day_of_week,start_time,department,semester"
      })
      if (!error) inserted++
    }
    return new Response(JSON.stringify({ success: true, slotsInserted: inserted, totalParsed: slots.length, type: "schedule" }), { headers: corsHeaders })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})

// ---------------------------------------------------------------------
// Excel extraction — returns rows of stringified cells (first sheet).
// Works for .xlsx files exported from Excel/Google Sheets, with an
// optional header row (headers are detected and skipped heuristically
// by the parse* functions below, which regex-match cell content rather
// than relying on fixed column order).
// ---------------------------------------------------------------------
async function extractRowsFromExcel(file: File): Promise<string[][]> {
  const buffer = await file.arrayBuffer()
  const wb = XLSX.read(new Uint8Array(buffer), { type: "array" })
  const sheet = wb.Sheets[wb.SheetNames[0]]
  const json: unknown[][] = XLSX.utils.sheet_to_json(sheet, { header: 1, blankrows: false })
  return json.map((row) => row.map((cell) => (cell ?? "").toString().trim()))
}

// ---------------------------------------------------------------------
// PDF extraction — lightweight text-object scrape (no scanned/OCR PDFs).
// Returns "rows" by splitting the flattened text on common line breaks
// so downstream regex parsing can treat it the same as Excel rows.
// ---------------------------------------------------------------------
async function extractRowsFromPDF(file: File): Promise<string[][]> {
  const buffer = await file.arrayBuffer()
  const bytes = new Uint8Array(buffer)
  const str = new TextDecoder("latin1").decode(bytes)
  const matches = str.matchAll(/BT[\s\S]*?ET/g)
  const texts: string[] = []
  for (const m of matches) {
    const cleaned = m[0].replace(/\(([^)]+)\)\s*Tj/g, '$1 ').replace(/[^\x20-\x7E\n]/g, ' ')
    texts.push(cleaned)
  }
  const flat = texts.join(" ").replace(/\s+/g, " ")
  // Single flattened blob — the schedule/transport regex parsers below
  // work directly off this text, so wrap it as one "row".
  return flat.length > 0 ? [[flat]] : []
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

// Transport rows: expects a header row of
//   Route Number | Route Name | <Stop 1> | <Stop 2> | ... | <Stop N>
// where each stop column header is the stop name and each data row's cell
// under it is that route's time at that stop (e.g. "07:30"). This gives an
// ordered stop->time list per route so the app can answer "which bus goes
// from stop A to stop B, and when". Falls back to regex scraping of a
// flattened blob (PDF path) the same way parseScheduleRows does for
// schedules, though PDFs can only recover flat departure_times, not stops
// (no reliable way to know which stop each time belongs to from raw text).
function parseTransportRows(rows: string[][]): any[] {
  const routes: any[] = []
  const timeRegex = /\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)?/g
  // Separate non-global regex for .test() — a global regex's .test() carries
  // lastIndex state across calls, so reusing timeRegex.test() in a loop
  // silently rejects every other otherwise-valid match.
  const isTime = (s: string) => /\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)?/.test(s)

  const isHeaderRow = (row: string[]) =>
    /^route\s*(no|number)?$/i.test(row[0] ?? "")

  const headerRow = rows.find(isHeaderRow)
  const stopNames = headerRow ? headerRow.slice(2).map((h) => h.trim()).filter(Boolean) : []

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

    // Excel/table row: [routeNumber, routeName, ...stopTimeCells]
    const [routeNumber, routeName, ...rest] = row
    if (!routeNumber || !routeName) continue
    if (isHeaderRow(row)) continue

    const stops = stopNames
      .map((name, i) => ({ name, time: (rest[i] ?? "").trim() }))
      .filter((s) => isTime(s.time))

    const times = rest
      .join(",")
      .split(/[,;]/)
      .map((t) => t.trim())
      .filter((t) => isTime(t))

    routes.push({
      route_number: routeNumber.trim(),
      route_name: routeName.trim(),
      departure_times: times.length ? times : null,
      stops,
      is_active: true,
    })
  }
  return routes
}
