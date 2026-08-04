import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// AFOS — push the newest release to every device, exactly once.
//
// WHY THIS EXISTS SEPARATELY FROM send-notification.
//
// `notify_new_release()` already writes the durable in-app row for every
// profile inside the same transaction as the app_releases row, so the record
// can never disagree with the release. What it could not do was reach a phone
// with the app CLOSED — and that is the only case that matters for an update,
// because someone who is already in the app is exactly the person who does not
// need to be told to open it.
//
// send-notification cannot serve this. It authenticates a real end-user JWT
// (`auth.getUser`), rate-limits per caller, and restricts broadcast to
// admin/teacher roles. A database trigger has no user and no JWT, so reaching
// it would mean storing a service-role key in Postgres — handing anything that
// can run SQL the keys to the whole project, to send one notification.
//
// HOW THIS IS AUTHORIZED, WITH NO SECRET ANYWHERE.
//
// Three independent layers, none of which requires storing a credential in the
// database:
//
//   1. verify_jwt stays ON. The caller (pg_net) presents the project's
//      publishable key, which is not a secret at all — it is compiled into
//      every copy of the app already (lib/config/supabase_config.dart), so
//      naming it in a migration discloses nothing. Verified against the live
//      gateway: an unauthenticated request is refused with
//      UNAUTHORIZED_NO_AUTH_HEADER before it ever reaches this code.
//
//   2. This endpoint takes no content from its caller. Not the title, not the
//      body, not the audience — every one of those is read from the database
//      row. So the most even an authorized caller can achieve is to deliver
//      the announcement that was already going out, marginally sooner.
//
//   3. It is idempotent. `claim_release_announcement()` stamps `push_sent_at`
//      in the same statement that reads the row, so a second caller gets
//      nothing back and sends nothing.
//
// Note this function deliberately does NOT call auth.getUser(). There is no end
// user behind a cron tick, and requiring one is exactly what makes
// send-notification unusable from the database.
//
// It is also driven two ways, and both are safe because of that idempotency:
//   * the trigger fires it immediately via pg_net (post-commit, async);
//   * a pg_cron job retries every 5 minutes for anything still unsent, so a
//     dropped request or a OneSignal outage delays the push instead of
//     losing it.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!
const ONESIGNAL_APP_ID = "2ae8d7b3-8999-4054-b185-2256b290993c"
const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY")!

// OneSignal rejects include_aliases lists longer than 2000 entries. This app
// has single-digit users today; the chunking is here so that stops being true
// without anyone having to remember this limit.
const ALIAS_CHUNK = 2000

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size))
  return out
}

Deno.serve(async () => {
  const headers = { "Content-Type": "application/json" }

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)

    // Claims the newest release if — and only if — it has not been pushed yet.
    // Returns zero rows on every subsequent call, which is what lets both the
    // trigger and a retrying cron job hammer this without double-notifying.
    const { data: claim, error: claimErr } = await supabase.rpc("claim_release_announcement")
    if (claimErr) {
      return new Response(JSON.stringify({ error: claimErr.message }), { status: 500, headers })
    }

    const release = Array.isArray(claim) ? claim[0] : claim
    if (!release) {
      return new Response(JSON.stringify({ announced: false, reason: "nothing pending" }), { headers })
    }

    // The push audience is resolved from the same place the trigger resolves
    // the in-app audience — every profile — so the two cannot describe
    // different people. That is the drift this repo's
    // check_notification_audiences.py exists to prevent.
    const { data: people, error: peopleErr } = await supabase.from("profiles").select("id")
    if (peopleErr) {
      await supabase.rpc("release_announcement_failed", { p_id: release.id })
      return new Response(JSON.stringify({ error: peopleErr.message }), { status: 500, headers })
    }
    const userIds = (people ?? []).map((p: { id: string }) => p.id)

    // Deliberately identical to the strings notify_new_release() writes into
    // user_notifications, so the banner and the notification centre entry read
    // the same rather than looking like two different events.
    const heading = `AFOS ${release.version} is available`
    const content = release.title && release.title.trim() !== ""
      ? release.title
      : "A new version of AFOS is ready to install."

    let targeted = 0
    // OneSignal recognised none of the external_ids we sent. That is NOT a
    // failure to retry — see the decision below.
    let noSubscribers = false
    const failures: string[] = []

    for (const batch of chunk(userIds, ALIAS_CHUNK)) {
      try {
        const res = await fetch("https://onesignal.com/api/v1/notifications", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Basic ${ONESIGNAL_REST_KEY}` },
          body: JSON.stringify({
            app_id: ONESIGNAL_APP_ID,
            include_aliases: { external_id: batch },
            target_channel: "push",
            headings: { en: heading },
            contents: { en: content },
            // Lands the user on Settings, where the Update button is — not on
            // the read-only What's New list, which would be a dead end from a
            // notification whose entire purpose is "install this".
            data: { deep_link_route: "/settings" },
          }),
        })
        const json = await res.json()

        // `errors` alone does NOT mean the send failed. When some external_ids
        // are unknown to OneSignal and others are fine, it returns 200 with
        // BOTH an `id` (the notification it created) and
        // `errors.invalid_aliases` listing the ones it skipped. Treating that
        // as a failure — which the first version of this did — released the
        // claim and had the cron job re-send to everyone who IS subscribed,
        // every five minutes, forever.
        //
        // The notification's own `id` is the only real proof of delivery.
        const created = typeof json.id === "string" && json.id.length > 0

        if (res.ok && created) {
          targeted += typeof json.recipients === "number" ? json.recipients : batch.length
          if (json.errors) {
            failures.push(`partial (${JSON.stringify(json.errors)})`)
          }
        } else if (json?.errors?.invalid_aliases) {
          // Nothing was created AND every alias was unknown: no device on this
          // project has logged in and registered its external_id. There is no
          // one to push to, and no amount of retrying invents a subscriber.
          noSubscribers = true
          failures.push(`no push subscription for any recipient (HTTP ${res.status}): ${JSON.stringify(json.errors)}`)
        } else {
          failures.push(`HTTP ${res.status}: ${JSON.stringify(json.errors ?? json)}`)
        }
      } catch (e) {
        failures.push(String(e))
      }
    }

    // Hand the claim back ONLY for a fault that retrying could fix — OneSignal
    // down, a network blip, a bad REST key. The cron job then picks it up
    // within five minutes.
    //
    // "Nobody is subscribed" is explicitly NOT such a fault. Retrying it every
    // five minutes until the end of time would never succeed, and the moment
    // one person did register they would receive an announcement for a release
    // that had long since been superseded. Those users are not missing out
    // either: the in-app notification is already written and durable, and the
    // update banner is waiting for them in Settings.
    //
    // A partial success is also kept as-is — re-sending would double-notify
    // everyone who already got it.
    if (targeted === 0 && userIds.length > 0 && !noSubscribers) {
      await supabase.rpc("release_announcement_failed", { p_id: release.id })
      return new Response(
        JSON.stringify({ announced: false, willRetry: true, version: release.version, errors: failures }),
        { status: 502, headers },
      )
    }

    return new Response(
      JSON.stringify({
        announced: true,
        version: release.version,
        pushTargeted: targeted,
        // Surfaced rather than buried: zero push recipients on a release is
        // worth noticing, even though it is not an error here.
        noSubscribers: noSubscribers || undefined,
        errors: failures.length ? failures : undefined,
      }),
      { headers },
    )
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers })
  }
})
