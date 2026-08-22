// Shared primitives for the mailbox-proof flow.
//
// The one rule this file exists to enforce: a code or token is NEVER stored,
// logged, or compared in plaintext. Everything at rest is an HMAC keyed with a
// server-side pepper, so a database leak on its own does not yield a usable
// credential — the attacker also needs the edge function's env.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

/// Pepper for the HMACs. Deliberately a hard failure rather than a silent
/// fallback: a default value here would mean every deployment shares a key,
/// which is the same as having none.
function pepper(): string {
  const p = Deno.env.get("IDENTITY_PEPPER");
  if (!p || p.length < 32) {
    throw new Error(
      "IDENTITY_PEPPER is missing or too short (need >= 32 chars). Set it with: supabase secrets set IDENTITY_PEPPER=<random>",
    );
  }
  return p;
}

/// Where the emailed links point. Must be the deployed web origin, because the
/// link has to open somewhere a browser can reach.
export function appOrigin(): string {
  return (Deno.env.get("PUBLIC_APP_URL") ?? "https://afos.vercel.app").replace(/\/+$/, "");
}

const enc = new TextEncoder();

export async function hmac(value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(pepper()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(value));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Length-independent, branch-free compare. Both inputs here are hex HMACs of
/// equal length, so this is hygiene rather than the load-bearing defence —
/// the load-bearing defence is the attempt counter in pending_registrations.
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// Six digits, uniformly distributed.
///
/// Rejection sampling rather than `% 1000000`: a plain modulo over a 32-bit
/// draw makes the low codes measurably likelier, which is exactly the bias a
/// guesser exploits. Leading zeros are preserved — "004821" is a valid code and
/// must be typed as shown.
export function generateCode(): string {
  const limit = 1_000_000;
  const max = Math.floor(0xFFFFFFFF / limit) * limit;
  const buf = new Uint32Array(1);
  let n: number;
  do {
    crypto.getRandomValues(buf);
    n = buf[0];
  } while (n >= max);
  return String(n % limit).padStart(6, "0");
}

/// 32 bytes, base64url. This is what goes in the emailed link, NOT the 6-digit
/// code — a six-digit value sitting in a URL is trivially brute-forced by
/// anything that can enumerate query strings.
export function generateToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Client IP, best-effort, for rate-limit keying only. Stored hashed.
export function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for") ?? "";
  return fwd.split(",")[0].trim() || req.headers.get("cf-connecting-ip") || "unknown";
}

/// Token-bucket check against the EXISTING limiter
/// (20260725080021_sec_token_bucket_rate_limiting.sql). The key must be passed
/// explicitly: consume_rate_limit() defaults it to auth.uid(), which is NULL
/// under a service-role client, and a NULL key is denied rather than allowed.
///
/// Fails CLOSED here, unlike send-notification's copy. This limiter is what
/// stands between a script and both your mail budget and a real student's
/// inbox — if it cannot answer, the safe response is to refuse, not to send.
// deno-lint-ignore no-explicit-any
export async function consumeRateLimit(
  supabase: any,
  bucket: string,
  key: string,
  cost = 1,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("consume_rate_limit", {
    p_bucket: bucket,
    p_key: key,
    p_cost: cost,
  });
  if (error) {
    console.error(`[rate_limit] ${bucket} check failed, denying:`, error.message);
    return false;
  }
  return data !== false;
}

/// AES-GCM key, derived from the same pepper via SHA-256 with a distinct
/// domain-separation string so it is NOT the same key material the HMACs use.
/// One secret to manage, two independent keys.
async function encKey(): Promise<CryptoKey> {
  const material = await crypto.subtle.digest("SHA-256", enc.encode(`afos:signup-enc:v1:${pepper()}`));
  return await crypto.subtle.importKey("raw", material, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

/// Encrypts the chosen password for the ≤10 minutes it sits staged.
///
/// WHY THIS EXISTS AT ALL. Inverting the flow means the auth user does not yet
/// exist when the password is chosen, so Supabase cannot hold it for us — but
/// a plaintext password at rest is unacceptable even for ten minutes, and even
/// in a service-role-only table. AES-GCM (authenticated, so a tampered
/// ciphertext fails rather than decrypting to garbage) with a key that lives
/// only in the function env means a database dump alone yields nothing.
///
/// The row is deleted the instant the account is created, and
/// purge_identity_ephemera() sweeps anything abandoned.
export async function encryptSecret(plain: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await encKey(), enc.encode(plain));
  const out = new Uint8Array(iv.length + ct.byteLength);
  out.set(iv, 0);
  out.set(new Uint8Array(ct), iv.length);
  return btoa(String.fromCharCode(...out));
}

export async function decryptSecret(blob: string): Promise<string> {
  const raw = Uint8Array.from(atob(blob), (c) => c.charCodeAt(0));
  const iv = raw.slice(0, 12);
  const ct = raw.slice(12);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, await encKey(), ct);
  return new TextDecoder().decode(pt);
}

/// Normalised form used for every lookup and every rate-limit key, so
/// "Rakib@DIU.edu.bd " and "rakib@diu.edu.bd" cannot be treated as two
/// different addresses and get two separate quotas.
export function normaliseEmail(raw: string): string {
  return String(raw ?? "").trim().toLowerCase();
}

/// Server-side re-check of the DIU rule. The client validator and the
/// enforce_email_domain trigger both do this too — this is the third, because
/// registration no longer passes through auth.signUp and therefore no longer
/// passes through that trigger on the way in.
export async function isEligibleAddress(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  email: string,
): Promise<boolean> {
  if (email.endsWith("@diu.edu.bd")) return true;
  const { data } = await supabase
    .from("auth_email_domain_allowlist")
    .select("email")
    .eq("email", email)
    .maybeSingle();
  return !!data;
}
