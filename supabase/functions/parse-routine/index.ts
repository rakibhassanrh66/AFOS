import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE")!

serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const formData = await req.formData()
    const file = formData.get("file") as File
    if (!file) return new Response(JSON.stringify({ error: "No file provided" }), { status: 400, headers: corsHeaders })

    const text = await extractTextFromPDF(file)
    if (!text || text.length < 50) {
      return new Response(JSON.stringify({ error: "Could not extract text from PDF. Ensure it is text-based, not scanned." }), { status: 400, headers: corsHeaders })
    }

    const slots = parseRoutineText(text)
    if (slots.length < 3) {
      return new Response(JSON.stringify({ error: "Routine format not recognized. Found fewer than 3 slots.", rawText: text.substring(0, 300) }), { status: 400, headers: corsHeaders })
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)
    let inserted = 0
    for (const slot of slots) {
      const { error } = await supabase.from("schedule_slots").upsert(slot, {
        onConflict: "subject_code,day_of_week,start_time,department,semester"
      })
      if (!error) inserted++
    }

    return new Response(JSON.stringify({ success: true, slotsInserted: inserted, totalParsed: slots.length }), { headers: corsHeaders })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})

async function extractTextFromPDF(file: File): Promise<string> {
  // Simple text extraction - reads raw bytes and finds text streams
  const buffer = await file.arrayBuffer()
  const bytes = new Uint8Array(buffer)
  const str = new TextDecoder("latin1").decode(bytes)
  // Extract text between BT/ET markers (PDF text objects)
  const matches = str.matchAll(/BT[\s\S]*?ET/g)
  const texts: string[] = []
  for (const m of matches) {
    const cleaned = m[0].replace(/\(([^)]+)\)\s*Tj/g, '$1 ').replace(/[^\x20-\x7E\n]/g, ' ')
    texts.push(cleaned)
  }
  return texts.join(" ").replace(/\s+/g, " ")
}

function parseRoutineText(text: string): any[] {
  const slots: any[] = []
  const dayMap: Record<string, number> = { sat:0, sun:1, mon:2, tue:3, wed:4, thu:5 }
  const timeRegex = /(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})/g
  const dayRegex = /\b(sat|sun|mon|tue|wed|thu)\w*/gi
  const subjectRegex = /\b([A-Z]{2,4}\s?\d{3,4}[A-Z]?)\b/g
  const roomRegex = /\b(\d{1,2}[-–]\d{3,4})\b/g

  const days = [...text.matchAll(dayRegex)].map(m => m[1].toLowerCase().substring(0, 3))
  const times = [...text.matchAll(timeRegex)].map(m => ({ start: m[1], end: m[2] }))
  const subjects = [...text.matchAll(subjectRegex)].map(m => m[1])
  const rooms = [...text.matchAll(roomRegex)].map(m => m[1])

  const count = Math.min(days.length, times.length, subjects.length)
  for (let i = 0; i < count; i++) {
    const dayNum = dayMap[days[i]] ?? 0
    const [building, room] = rooms[i] ? rooms[i].split(/[-–]/) : ['4', '101']
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
