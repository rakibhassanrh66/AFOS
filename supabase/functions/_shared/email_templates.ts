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
  // One cell per character, with a 6px spacer between them. The spacer is its
  // own <td> rather than a margin, because Word ignores margins on table cells
  // and the chips would touch in Outlook.
  //
  // Split on the raw code and escape EACH character: the code is generated
  // server-side and is always digits, but escaping per-cell rather than
  // trusting that keeps the guarantee local to this line, where anyone reading
  // it can see it holds.
  const digitCells = !o.code ? "" : o.code
    .split("")
    .map((ch, idx) =>
      `${idx === 0 ? "" : `<td width="6" style="width:6px;font-size:0;line-height:0;">&nbsp;</td>`}` +
      `<td class="afos-chip" align="center" style="width:46px;height:58px;background:#FFFFFF;` +
      `border:1px solid ${HAIRLINE};border-bottom:3px solid ${BRAND_GREEN_DEEP};border-radius:10px;` +
      `font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:30px;` +
      `font-weight:700;color:${INK};text-align:center;vertical-align:middle;">${escapeHtml(ch)}</td>`
    )
    .join("");

  const codeBlock = !o.code ? "" : `
  <!-- THE CODE. The single loudest element on the page, because most people
       type it rather than click — especially on a phone.

       PER-DIGIT CHIPS, and the reason they are safe. Each digit sits in its
       own cell, which is far easier to read off a screen and to transcribe by
       eye than one long run — but it means a long-press selection returns
       "4 8 2 9 1 3" with the cell separators included.

       That would break the paste, and nearly cost us this design. It does not,
       because the APP tolerates it: the code field runs
       FilteringTextInputFormatter.digitsOnly, so a manual paste is normalised,
       and the "Paste code from email" button parses through extractOtpCode(),
       which accepts spaces, non-breaking spaces, newlines and dashes between
       digits while still refusing to slice six digits out of a longer number.
       See test/otp_code_test.dart — the "4 8 2 9 1 3" case is pinned there
       precisely so nobody tightens that parser and silently breaks this mail.
       (Double quotes, not backticks: this comment sits INSIDE a template
       literal, so a backtick here terminates the string and the function fails
       to bundle. The deploy rejects it, but only after the commit.)

       The fix belonged in the parser, not in the design: there is one parser
       and it is testable, while the mail is seen by every applicant. -->
  <tr><td class="afos-pad" style="padding:26px 40px 0 40px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="afos-panel afos-rise" style="background:${PANEL};border:1px solid ${HAIRLINE};border-radius:14px;">
      <tr><td style="padding:0;font-size:0;line-height:0;">
        <!-- 3px brand rule, drawn as a cell so Outlook renders it. -->
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
          <td height="3" style="height:3px;line-height:3px;font-size:0;background:${BRAND_GREEN_DEEP};border-radius:14px 14px 0 0;">&nbsp;</td>
        </tr></table>
      </td></tr>
      <tr><td align="center" style="padding:24px 16px 22px 16px;font-family:Segoe UI,Helvetica,Arial,sans-serif;">
        <div class="afos-muted" style="font-size:11px;letter-spacing:1.4px;text-transform:uppercase;color:${INK_MUTED};font-weight:600;margin-bottom:16px;">Your confirmation code</div>
        <!-- A centred table, not inline-blocks: Outlook's Word engine drops
             inline-block entirely and would stack the digits vertically. -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:0 auto;"><tr>
          ${digitCells}
        </tr></table>
        <div class="afos-muted" style="font-size:12px;color:${INK_MUTED};margin-top:16px;">Tap and hold to copy, then press <strong style="color:${INK};">Paste code from email</strong> in the app</div>
        <div class="afos-muted" style="font-size:12px;color:${INK_MUTED};margin-top:4px;">Expires in ${o.expiresMinutes} minutes · works once</div>
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
    /* Six 46px chips plus five 6px gaps is 306px, which overflows a 320px
       screen once the card's own padding is counted. Narrowing the chips keeps
       the row on one line rather than wrapping three digits onto a second. */
    .afos-chip{width:40px!important;height:52px!important;font-size:26px!important}
  }

  /* MOTION, AND THE RULE THAT MAKES IT SAFE.
     Gmail and Outlook (Word engine) strip @keyframes outright; Apple Mail,
     iOS Mail, Samsung Mail and Thunderbird honour them. So animation here is
     decoration for roughly half of readers and must be invisible to the rest.

     The rule: an element's FINISHED state is what is inlined, and these blocks
     only replay the arrival. Nothing starts at opacity:0 inline. Get that
     backwards — the usual way this is written — and every Gmail reader opens a
     mail with an invisible confirmation code, which is a total failure for a
     decorative gain.

     Also honoured: prefers-reduced-motion, same as the app. */
  @keyframes afosRise{
    from{opacity:0;transform:translateY(10px)}
    to{opacity:1;transform:translateY(0)}
  }
  @keyframes afosShimmer{
    0%,72%{text-shadow:none}
    82%{text-shadow:0 0 14px rgba(62,207,142,0.55)}
    100%{text-shadow:none}
  }
  .afos-rise{animation:afosRise 620ms cubic-bezier(0.22,1,0.36,1) both}
  .afos-shimmer{animation:afosShimmer 3.6s ease-in-out 700ms infinite}
  .afos-btn{transition:transform 160ms ease,box-shadow 160ms ease}
  .afos-btn:hover{transform:translateY(-1px);box-shadow:0 6px 18px rgba(14,143,94,0.34)}
  @media (prefers-reduced-motion:reduce){
    .afos-rise,.afos-shimmer{animation:none!important}
    .afos-btn{transition:none!important}
  }
  @media (prefers-color-scheme:dark){
    .afos-page{background:#070D18!important}
    .afos-card{background:#0E1928!important;border-color:#1E2E47!important}
    .afos-ink{color:#E8EFF9!important}
    .afos-muted{color:#94A7C2!important}
    .afos-panel{background:#122032!important;border-color:#25384F!important}
    .afos-chip{background:#0B1626!important;border-color:#2B4160!important;color:#E8EFF9!important}
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
  <!-- BULLETPROOF BUTTON. Outlook on Windows renders through Word, which
       ignores padding on an inline <a> — the button collapses to bare
       underlined text sitting on a coloured rectangle the size of the words.
       The VML rectangle below is the standard answer: Outlook draws that and
       skips the <a>, every other client skips the VML and draws the <a>.
       Both carry the same href and label, so they cannot drift. -->
  <tr><td class="afos-pad" align="center" style="padding:24px 40px 4px 40px;">
    <!--[if mso]>
    <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word"
      href="${escapeHtml(o.actionUrl)}" style="height:48px;v-text-anchor:middle;width:280px;" arcsize="19%"
      stroke="f" fillcolor="${BRAND_GREEN_DEEP}">
      <w:anchorlock/>
      <center style="color:#FFFFFF;font-family:Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;">${escapeHtml(o.actionLabel)}</center>
    </v:roundrect>
    <![endif]-->
    <!--[if !mso]><!-- -->
    <a class="afos-btn" href="${escapeHtml(o.actionUrl)}" style="display:inline-block;background:${BRAND_GREEN_DEEP};color:#FFFFFF;font-family:Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;text-decoration:none;padding:15px 36px;border-radius:9px;box-shadow:0 3px 10px rgba(14,143,94,0.26);">${escapeHtml(o.actionLabel)}</a>
    <!--<![endif]-->
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
