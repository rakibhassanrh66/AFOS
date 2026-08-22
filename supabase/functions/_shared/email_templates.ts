// Transactional email templates for AFOS.
//
// DESIGN CONSTRAINTS THAT DROVE EVERY CHOICE HERE — these are not stylistic
// preferences, they are what makes mail actually render at a university:
//
//  - Tables, not flex/grid. Outlook (which DIU staff run) uses the Word
//    rendering engine; a div-based layout collapses there.
//  - Inline styles on every element. Gmail strips <style> blocks in a large
//    share of contexts, so anything that must survive is inlined. The <style>
//    block carries dark-mode hints only, as progressive enhancement.
//  - ZERO external images. Most clients block remote images by default, and a
//    verification mail whose code lives in an image is a broken mail. The
//    wordmark is type, the logo mark is a CSS-drawn box. Nothing to block.
//  - 600px max width, the widest that survives Outlook's reading pane.
//  - A real plain-text alternative. Text/plain is not a legacy courtesy: spam
//    filters score multipart messages that lack it, and the code must survive
//    for someone reading on a watch or a screen reader.
//
// Palette is lifted from lib/config/theme/app_colors.dart so the mail looks
// like the app it came from: brand green #3ECF8E, navy ground, amber #E0A83C.
// The button uses a DARKENED green (#0E8F5E) because #3ECF8E cannot carry
// white text at 4.5:1 — the brand colour is kept for accents where it passes.

const BRAND_GREEN_DEEP = "#0E8F5E";
const NAVY = "#0B1B33";
const NAVY_SOFT = "#16294A";
const INK = "#12203A";
const INK_MUTED = "#5A6B85";
const HAIRLINE = "#DCE5F0";
const PANEL = "#F1F6FC";
const PAGE = "#EDF1F7";

/// Anything interpolated into HTML must pass through this. `full_name` is
/// attacker-controlled at signup — an unescaped name is an HTML injection into
/// a mail we send on the university's behalf.
export function escapeHtml(raw: string): string {
  return String(raw ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// Honorifics and title prefixes that are NOT a person's name. Bangladeshi
/// names very often lead with one — "Md. Rakib Hassan", "Mst. Ayesha Akter" —
/// and naive first-token logic greets them as "Hi Md.", which reads as a
/// broken mail-merge on the first message the university ever sends them.
const NOT_A_NAME = new Set([
  "md", "mohammad", "muhammad", "mohd", "mst", "most", "mrs", "mr", "ms",
  "miss", "dr", "prof", "engr", "eng",
]);

/// First usable given name, never an empty greeting.
///
/// Returns PLAIN text — HTML callers must escape it. Falls back to a
/// role-neutral address rather than "Hi ," which is itself a classic
/// phishing tell.
export function greetingName(fullName?: string | null): string {
  const tokens = String(fullName ?? "").trim().split(/\s+/).filter(Boolean);
  for (const raw of tokens) {
    // Strip punctuation so "Md." and "Md" are treated alike.
    const clean = raw.replace(/[^\p{L}\p{N}]/gu, "");
    if (clean.length < 2) continue;                       // a bare initial
    if (NOT_A_NAME.has(clean.toLowerCase())) continue;    // an honorific
    return clean;
  }
  return "there";
}

interface Shell {
  /// Shown in the inbox list next to the subject. Without it, clients scrape
  /// the first body text, which would be the wordmark.
  preheader: string;
  heading: string;
  intro: string;
  /// Omitted for mails that carry no code (the account-exists notice), which
  /// then drop the code panel and the or-divider entirely rather than render
  /// an empty box.
  code?: string;
  actionUrl: string;
  actionLabel: string;
  expiresMinutes?: number;
  /// The one-line explanation of what happens if this wasn't them.
  safetyNote: string;
}

function shell(o: Shell): string {
  const codeBlock = !o.code ? "" : `
  <!-- The code. Deliberately the single loudest element on the page: most
       people will type this rather than click, especially on mobile. -->
  <tr><td class="afos-pad" style="padding:26px 40px 0 40px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="afos-panel" style="background:${PANEL};border:1px solid ${HAIRLINE};border-radius:11px;">
      <tr><td align="center" style="padding:22px 16px 20px 16px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
        <div class="afos-muted" style="font-size:11px;letter-spacing:1.4px;text-transform:uppercase;color:${INK_MUTED};font-weight:600;margin-bottom:12px;">Your confirmation code</div>
        <div class="afos-code afos-ink" style="font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:36px;font-weight:700;letter-spacing:11px;color:${INK};line-height:1.1;padding-left:11px;">${escapeHtml(o.code)}</div>
        <div class="afos-muted" style="font-size:12px;color:${INK_MUTED};margin-top:13px;">Expires in ${o.expiresMinutes} minutes · works once</div>
      </td></tr>
    </table>
  </td></tr>

  <tr><td class="afos-pad" style="padding:22px 40px 0 40px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
      <td style="border-top:1px solid ${HAIRLINE};font-size:0;line-height:0;height:1px;">&nbsp;</td>
      <td width="46" align="center" class="afos-muted" style="font-size:11px;color:${INK_MUTED};text-transform:uppercase;letter-spacing:1px;padding:0 8px;">or</td>
      <td style="border-top:1px solid ${HAIRLINE};font-size:0;line-height:0;height:1px;">&nbsp;</td>
    </tr></table>
  </td></tr>`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${escapeHtml(o.heading)}</title>
<style>
  /* Progressive enhancement only — every critical style is also inlined. */
  @media (max-width:620px){
    .afos-pad{padding-left:24px!important;padding-right:24px!important}
    .afos-code{font-size:30px!important;letter-spacing:8px!important}
  }
  @media (prefers-color-scheme:dark){
    .afos-page{background:#070D18!important}
    .afos-card{background:#0E1928!important;border-color:#1E2E47!important}
    .afos-ink{color:#E8EFF9!important}
    .afos-muted{color:#94A7C2!important}
    .afos-panel{background:#122032!important;border-color:#25384F!important}
  }
</style>
</head>
<body style="margin:0;padding:0;background:${PAGE};">
<div style="display:none;font-size:1px;color:${PAGE};line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">${escapeHtml(o.preheader)}</div>
<table role="presentation" class="afos-page" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${PAGE};margin:0;padding:0;">
<tr><td align="center" style="padding:32px 12px;">

<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" class="afos-card" style="width:600px;max-width:600px;background:#FFFFFF;border:1px solid ${HAIRLINE};border-radius:14px;overflow:hidden;">

  <!-- Header band. The mark is drawn with a table cell, not an <img>, so it
       survives image blocking. -->
  <tr><td style="background:${NAVY};padding:22px 32px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
      <td style="width:38px;height:38px;background:${NAVY_SOFT};border:1px solid rgba(62,207,142,0.45);border-radius:9px;text-align:center;vertical-align:middle;font-family:Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;color:#3ECF8E;letter-spacing:0.5px;">A</td>
      <td style="padding-left:12px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
        <div style="font-size:16px;font-weight:700;color:#FFFFFF;letter-spacing:0.4px;line-height:1.2;">AFOS</div>
        <div style="font-size:11px;color:#9DB4D2;letter-spacing:0.3px;line-height:1.4;">Daffodil International University</div>
      </td>
    </tr></table>
  </td></tr>

  <tr><td class="afos-pad" style="padding:38px 40px 8px 40px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
    <h1 class="afos-ink" style="margin:0 0 12px 0;font-size:23px;line-height:1.3;font-weight:700;color:${INK};">${escapeHtml(o.heading)}</h1>
    <p class="afos-muted" style="margin:0;font-size:15px;line-height:1.6;color:${INK_MUTED};">${o.intro}</p>
  </td></tr>
${codeBlock}
  <tr><td class="afos-pad" align="center" style="padding:22px 40px 4px 40px;">
    <a href="${escapeHtml(o.actionUrl)}" style="display:inline-block;background:${BRAND_GREEN_DEEP};color:#FFFFFF;font-family:Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;text-decoration:none;padding:14px 34px;border-radius:9px;">${escapeHtml(o.actionLabel)}</a>
  </td></tr>

  <tr><td class="afos-pad" align="center" style="padding:14px 40px 0 40px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
    <p class="afos-muted" style="margin:0;font-size:12px;line-height:1.6;color:${INK_MUTED};">Button not working? Copy this link into your browser:<br>
      <span style="color:#2B6CB0;word-break:break-all;">${escapeHtml(o.actionUrl)}</span></p>
  </td></tr>

  <tr><td class="afos-pad" style="padding:26px 40px 34px 40px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#FFF8EC;border:1px solid #F0DCB8;border-radius:9px;">
      <tr><td style="padding:14px 16px;font-size:12.5px;line-height:1.6;color:#7A5A1E;">${o.safetyNote}</td></tr>
    </table>
  </td></tr>

  <tr><td style="background:#F7FAFD;border-top:1px solid ${HAIRLINE};padding:20px 40px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
    <p class="afos-muted" style="margin:0;font-size:11.5px;line-height:1.7;color:${INK_MUTED};">
      AFOS — All Facilities, One System<br>
      Daffodil International University, Daffodil Smart City, Ashulia, Dhaka 1341<br>
      This is an automated message. Replies are not monitored.
    </p>
  </td></tr>

</table>
</td></tr></table>
</body></html>`;
}

export interface CodeMailInput {
  fullName?: string | null;
  code: string;
  actionUrl: string;
  expiresMinutes: number;
}

export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

export function verificationEmail(i: CodeMailInput): RenderedMail {
  // Escaped here, not inside greetingName: the plain-text bodies below need
  // the raw value, and double-escaping would render "O&amp;#39;Brien".
  const name = escapeHtml(greetingName(i.fullName));
  return {
    // The code is in the subject on purpose: it lets someone confirm straight
    // from the notification shade without opening the mail at all.
    subject: `${i.code} is your AFOS confirmation code`,
    html: shell({
      preheader: `Your AFOS confirmation code is ${i.code}. It expires in ${i.expiresMinutes} minutes.`,
      heading: "Confirm your AFOS account",
      intro: `Hi ${name}, you're almost in. Enter the code below in the app, or use the button, to confirm this is your Daffodil International University address.`,
      code: i.code,
      actionUrl: i.actionUrl,
      actionLabel: "Confirm my account",
      expiresMinutes: i.expiresMinutes,
      safetyNote:
        "<strong>Didn't sign up?</strong> Someone entered this address on the AFOS registration form. No account exists yet and none will be created unless this code is used — you can safely ignore this message.",
    }),
    text: [
      `Confirm your AFOS account`,
      ``,
      `Hi ${greetingName(i.fullName)},`,
      ``,
      `Your confirmation code is: ${i.code}`,
      `It expires in ${i.expiresMinutes} minutes and works once.`,
      ``,
      `Or confirm here: ${i.actionUrl}`,
      ``,
      `Didn't sign up? Someone entered this address on the AFOS registration`,
      `form. No account exists yet and none will be created unless this code`,
      `is used — you can safely ignore this message.`,
      ``,
      `AFOS — All Facilities, One System`,
      `Daffodil International University`,
    ].join("\n"),
  };
}

export function passwordResetEmail(i: CodeMailInput): RenderedMail {
  // Escaped here, not inside greetingName: the plain-text bodies below need
  // the raw value, and double-escaping would render "O&amp;#39;Brien".
  const name = escapeHtml(greetingName(i.fullName));
  return {
    subject: `${i.code} is your AFOS password reset code`,
    html: shell({
      preheader: `Your AFOS password reset code is ${i.code}. It expires in ${i.expiresMinutes} minutes.`,
      heading: "Reset your AFOS password",
      intro: `Hi ${name}, we received a request to reset the password on this account. Enter the code below in the app, or use the button, to choose a new one.`,
      code: i.code,
      actionUrl: i.actionUrl,
      actionLabel: "Choose a new password",
      expiresMinutes: i.expiresMinutes,
      safetyNote:
        "<strong>Didn't request this?</strong> Your password has not changed and your account is safe. Someone may have mistyped their address — you can ignore this message.",
    }),
    text: [
      `Reset your AFOS password`,
      ``,
      `Hi ${greetingName(i.fullName)},`,
      ``,
      `Your password reset code is: ${i.code}`,
      `It expires in ${i.expiresMinutes} minutes and works once.`,
      ``,
      `Or reset here: ${i.actionUrl}`,
      ``,
      `Didn't request this? Your password has not changed and your account is`,
      `safe. You can ignore this message.`,
      ``,
      `AFOS — All Facilities, One System`,
      `Daffodil International University`,
    ].join("\n"),
  };
}

/// Sent when someone tries to register an address that ALREADY has an account.
///
/// This is what makes the flow non-enumerable: register-request returns the
/// identical response either way, so an attacker probing for "does this
/// student have an account" learns nothing from the API. The real owner still
/// gets told something happened, which is the honest thing to do.
export function accountExistsEmail(i: { fullName?: string | null; loginUrl: string }): RenderedMail {
  // Escaped here, not inside greetingName: the plain-text bodies below need
  // the raw value, and double-escaping would render "O&amp;#39;Brien".
  const name = escapeHtml(greetingName(i.fullName));
  return {
    subject: "You already have an AFOS account",
    html: shell({
      preheader: "Someone tried to register with your address — your existing account is unchanged.",
      heading: "You already have an AFOS account",
      intro: `Hi ${name}, someone just tried to create an AFOS account with this address. You already have one, so nothing was created and nothing changed.`,
      actionUrl: i.loginUrl,
      actionLabel: "Sign in instead",
      safetyNote:
        "<strong>Wasn't you?</strong> Your account is untouched. If you can't remember your password, use “Forgot password” on the sign-in screen rather than registering again.",
    }),
    text: [
      `You already have an AFOS account`,
      ``,
      `Someone just tried to create an AFOS account with this address.`,
      `You already have one, so nothing was created and nothing changed.`,
      ``,
      `Sign in: ${i.loginUrl}`,
      ``,
      `If you can't remember your password, use "Forgot password" on the`,
      `sign-in screen rather than registering again.`,
      ``,
      `AFOS — All Facilities, One System`,
    ].join("\n"),
  };
}
