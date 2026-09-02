# AFOS mail — setup, limits, and triage

Everything the transactional mail path needs to work, in one place. Written
after two separate outages that were each diagnosed from scratch because this
file did not exist. Previously the only record was scattered across
`REDESIGN_LOG.md:1866-1977`, and `README.md` mentions none of the four mail
secrets.

AFOS sends exactly **two** kinds of mail — prove a mailbox, and recover a
password. Everything else is OneSignal push, deliberately, because push has no
per-day ceiling and mail does.

---

## 1. How the mail path is wired

Registration does **not** use Supabase Auth's built-in confirmation mail.
`emailRedirectTo` appears nowhere in the repo. The whole flow is custom edge
functions, which is why Supabase's "Confirm signup" template and its
`{{ .SiteURL }}` are irrelevant to registration.

```
register-request ─┐
password-reset   ─┼─> _shared/mailer.ts  dispatch()
                  │      ├─ per-minute budget ok? ─ no ─> email_outbox
                  │      ├─ daily budget ok?      ─ no ─> email_outbox
                  │      └─ POST api.resend.com/emails      (inline lane, ~1s)
                  │
                  └─> email_outbox ──> email-dispatch (pg_cron, every minute)
                                          └─ POST api.resend.com/emails
```

- `_shared/mailer.ts` — the only place that talks to Resend. Raw `fetch`, not
  the SDK.
- `_shared/email_templates.ts` — the HTML/text templates. Tables not flexbox,
  everything inlined, zero external images, because DIU runs Outlook and Gmail.
- `_shared/identity.ts` — HMAC pepper, code/token generation, rate limits, and
  `appOrigin()`.
- `mail-domain-status` — the diagnostic. Start here when anything is wrong.

---

## 2. Secrets

Set with `supabase secrets set NAME=value --project-ref dtsptjallznnvattadlu`.
`supabase secrets list` shows SHA-256 digests, never plaintext.

| Secret | Purpose | Fallback if unset |
|---|---|---|
| `RESEND_API_KEY` | Provider auth. Read per-call, so rotation takes effect on the next invocation with no redeploy. | none — send fails, marked retryable |
| `IDENTITY_PEPPER` | HMAC key for codes/tokens at rest, and (via SHA-256 domain separation) the AES-GCM key for the staged password. Must be >= 32 chars. | **none — throws.** Deliberate: a default would mean every deployment shares a key |
| `MAIL_FROM` | Sender. Must be on a domain verified with Resend. | `AFOS <no-reply@afos.srown.com>` |
| `PUBLIC_APP_URL` | Origin for every emailed link. **Must be the production alias, not a Vercel branch/preview URL** — see §6. | `https://diu-afos.vercel.app` |
| `SUPPORT_EMAIL` | Shown to an applicant whose mail failed. | `rakibhassan.rh66@protonmail.com` |
| `SUPPORT_TELEGRAM` | Same. | `@deadbrat` |

Both fallbacks used to point at domains this project does not own
(`afos.vercel.app`, `afos.app`). They now name the real ones, so a missing
secret degrades to something that works instead of to a fresh mystery. The env
var still wins in every case.

---

## 3. DNS — `afos.srown.com`, registrar Spaceship

A **subdomain** is used on purpose: it isolates AFOS's sending reputation, and
leaves `srown.com` free for other projects to send independently.

| Host (Spaceship appends `.srown.com`) | Type | Value | Proves |
|---|---|---|---|
| `send.afos` | CNAME | `send.forge.rmta.net` | SPF, via the target's own record |
| `rsend.afos` | CNAME | `rsend-apne1.forge.rmta.net` | bounce/feedback MX, region-matched to Tokyo |
| `resend._domainkey.afos` | TXT | `p=MIGf…AQAB` | DKIM |
| `_dmarc.afos` | TXT | `v=DMARC1; p=none;` | DMARC |

Verify from outside, not from the dashboard:

```bash
curl -s -H 'accept: application/dns-json' \
  "https://dns.google/resolve?name=resend._domainkey.afos.srown.com&type=TXT"
```

### DMARC

`diu.edu.bd` is Google Workspace, so **every recipient is Gmail**, and Gmail has
required DMARC of senders since February 2024. Alignment already passes — DKIM
signs as `d=afos.srown.com` and the return path is under `send.afos.srown.com`,
so both align relaxed with the From domain.

Start at `p=none` (monitor only). Move to `p=quarantine`, then `p=reject`, only
after Gmail's *Show original* shows SPF, DKIM and DMARC all PASS on real mail.

`rua=` is omitted deliberately: a report address on `gmail.com` needs an
authorization record at `gmail.com`, which you cannot create. To collect
reports, set up Spaceship email forwarding for `dmarc@srown.com` and append
`rua=mailto:dmarc@srown.com;`.

### Adding a second sending domain

The Resend **free plan allows 3 domains**. Another project adds its own
subdomain or root and gets its own DKIM and its own reputation — nothing about
AFOS needs to change. This is exactly why AFOS lives on a subdomain and why its
DMARC record is on `_dmarc.afos`, not on the root.

---

## 4. Limits, and the one number to change

| | Free | Pro ($20/mo) |
|---|---|---|
| Emails / month | 3,000 | 50,000 |
| Emails / **day** | **100** | unlimited |
| Domains | 3 | 10 |
| API rate | 10 req/s per team | 10 req/s |
| Log retention | 30 days | — |

Three limiters sit in front of the provider, all token buckets in
`rate_limit_policies`:

| Bucket | Capacity | Refill/min | Guards |
|---|---|---|---|
| `email_verify_addr` | 3 | 0.05 | one address being mail-bombed |
| `email_verify_ip` | 10 | 0.5 | one device looping signups |
| `email_provider_resend` | 100 | 100 | inline burst; overflow diverts to the outbox |
| `email_provider_resend_daily` | 100 | 100/1440 | **the provider's real daily ceiling** |

**When the Resend plan changes, this is the only thing to update** — a row, not
a deploy:

```sql
update rate_limit_policies
   set capacity = 50000, refill_per_minute = 50000/1440.0
 where bucket = 'email_provider_resend_daily';
```

Raise `capacity` **and** `refill_per_minute` together, or the bucket refills at
the old rate and silently throttles you at the new plan.

---

## 5. Triage — in this order

**1. Ask the provider what it sees.** This is the endpoint that ends most
arguments, because it reads the key the same way the mailer does:

```bash
curl -s -H "Authorization: Bearer <publishable key>" \
  "https://dtsptjallznnvattadlu.supabase.co/functions/v1/mail-domain-status"
```

```json
{ "ok": true,
  "mailFrom": "AFOS <no-reply@afos.srown.com>",
  "appOrigin": "https://diu-afos.vercel.app",
  "appOriginIsFallback": false,
  "domainCount": 1,
  "domains": [{ "name": "afos.srown.com", "status": "verified" }] }
```

Read it as follows:

| Symptom | Meaning | Fix |
|---|---|---|
| `domainCount: 0` | the key belongs to a **different Resend account or team** than the domain | re-issue the key from the right account; re-verifying achieves nothing |
| `status: "not_started"` | Resend has **never run** the DNS check. Adding records is not enough, and neither is adding the domain | `?verify=1` on the same endpoint |
| `status: "pending"` | check is running, or a record is subtly wrong | re-check §3 from an outside resolver |
| `httpStatus: 401` | key invalid or revoked | rotate `RESEND_API_KEY` |
| `mailFrom` domain != a verified domain | every send returns `validation_error` 403 | fix `MAIL_FROM` |
| `appOriginIsFallback: true` | `PUBLIC_APP_URL` is unset; links work only by luck | set it |

**2. Check the queue.**

```sql
select state, count(*) from email_outbox group by state;
select to_email, template, attempts, last_error, send_after
  from email_outbox where state in ('queued','dropped')
  order by send_after desc limit 20;
```

`last_error` carries the provider's own words. Rows stuck in `sending` mean a
worker died mid-batch — the drain returns unattempted rows to `queued` on a
budget stall, but a hard crash cannot.

**3. Check the day's allowance.**

```sql
select * from mail_budget_status();
select bucket, key, tokens, updated_at from rate_limit_buckets
 where bucket like 'email_provider%';
```

`remaining` pinned at exactly `100` **with no row in `rate_limit_buckets`** was
the signature of the inert-quota bug fixed on 2026-09-02: the bucket was
defined and read but never consumed. A healthy system has a row that decreases.

**4. Read Resend's error names.** `validation_error` 403 covers both *"The X
domain is not verified"* and *"You can only send testing emails to your own
email address"*. `daily_quota_exceeded` / `monthly_quota_exceeded` /
`rate_limit_exceeded` are all 429 and retryable; `422` is not.

---

## 6. Two incidents worth not repeating

**The domain that was never checked (2026-09-01).** Four sends failed with *"The
afos.srown.com domain is not verified"* while the DNS resolved correctly from
outside and the dashboard looked green. The domain sat at `status:
"not_started"` — Resend had never run the check. Nothing had asked it to.
`mail-domain-status` exists to make that visible in one call.

**The link that led to a login wall (2026-09-02).** Sending was fully healthy —
verified domain, correct sender, mail delivered. `PUBLIC_APP_URL` was set to a
Vercel **git-branch** URL (`afos-git-main-….vercel.app`) rather than the
production alias. That host has Vercel Deployment Protection on, so every
student who tapped *Confirm my account* was redirected to `vercel.com/login`
and asked to sign in to an account they do not have. Nothing errored anywhere.

The lesson both share: **the mail sending and the mail being useful are two
different systems, and only the first one reports failure.** That is why
`mail-domain-status` now returns `appOrigin` alongside `mailFrom` — the sender
and the link, checked together.

A branch URL is a valid-looking, working, wrong answer. Always point
`PUBLIC_APP_URL` at the production alias, and confirm it serves the app
unauthenticated:

```bash
curl -s -o /dev/null -w "%{http_code} %{num_redirects} %{url_effective}\n" \
  -L "https://diu-afos.vercel.app/#/auth/verify?token=test"
# want: 200 0 https://diu-afos.vercel.app/#/auth/verify?token=test
# a redirect to vercel.com/login means protection is on for that host
```

---

## 7. Related settings not in this repo

There is no `supabase/config.toml`, so these live only in the Supabase
dashboard and are invisible to version control:

- **Auth → Site URL** — used by the *legacy* Supabase recovery flow at
  `/reset-password`, which is separate from the custom code-first reset.
- **Auth → Redirect allowlist** — must contain `afos://reset-password`, which
  `lib/features/auth/data/repositories/auth_repository.dart` passes on native.
