"""Fails CI when a UI element cannot survive its own accessibility settings.

TWO STANDING ASSERTIONS, both of which this project has broken by hand:

  1. No fixed-size box holds text that cannot fit at the 2.0x text scale.
  2. No tappable control is smaller than the constitution's 48dp floor.

WHY THIS IS ARITHMETIC AND NOT AN OPINION. A box of height H holding text of
size F overflows when `F * scale * lineBox > H - verticalPadding`. Flutter's
default line box is ~1.2 * fontSize; a Text with a trimmed `textHeightBehavior`
gets ~1.0. Android's accessibility slider reaches 2.0x and this repo's probe
harness sweeps to 2.0x, so 2.0 is the number that matters. The audit that
produced this script found six boxes that burst between 1.67x and 1.94x --
including `_logoLetter` on the LOGIN screen, so a reader with large text met a
broken wordmark before they could sign in.

WHY IT PARSES INSTEAD OF GREPPING. The first version of this audit used a fixed
line-lookahead window and reported 65 touch-target and 70 overflow problems.
Both counts were almost entirely noise: a `Border.all(width: 0.5)` inside the
window was read as a 0.5dp touch target, and `SizedBox(height: 24)` used as a
SPACER was read as a box wrapping the next sibling. The real counts were 1 and
6. So this walks to the matching paren and splits the argument list at depth 0
-- a `width:` nested inside `decoration:` is invisible to it, and a `child:`
either exists or does not.

Every check carries a known-bad and a known-good sample and the script REFUSES
TO REPORT NUMBERS if either fails. Run `--selftest` to see them.

No database and no secrets: this reads source only, so it belongs in the
analyze job rather than beside the three PostgREST guards.
"""
import os
import re
import sys

MAX_SCALE = 2.0
TOUCH_FLOOR = 48.0
IDENT = re.compile(r"(?<![A-Za-z0-9_$.])([A-Z][A-Za-z0-9_]*)\s*\(")

# Font size of each theme role, read from lib/config/theme/app_text_styles.dart.
# Resolved so a box using `AppTextStyles.labelSmall` is judged too -- without
# this the check only sees boxes that hardcode `fontSize:`, which is a minority
# of them, and its "0 findings" would be worth nothing.
STYLE_SIZES = {
    "displayLarge": 32, "displayMedium": 24, "headlineLarge": 20,
    "headlineMed": 18, "titleLarge": 16, "titleMedium": 14,
    "bodyLarge": 15, "bodyMedium": 13, "labelSmall": 11,
    "monoMedium": 13, "monoSmall": 11,
}

TAPPABLE = {"GestureDetector", "InkWell", "InkResponse", "Pressable"}
BOXES = {"SizedBox", "Container"}
MATERIAL_BUTTONS = {"IconButton", "TextButton", "ElevatedButton", "OutlinedButton"}

# Deliberate exceptions. A reason is REQUIRED -- an exception without one is
# indistinguishable from an oversight, which is how these got shipped.
ALLOW = {
    # "lib/path/file.dart:LineText": "why this is genuinely fine",
}


def strip_comments(src):
    """Blank out comments while preserving every character position."""
    out = list(src)
    i, n, in_s = 0, len(src), None
    while i < n:
        c = src[i]
        if in_s:
            if c == "\\":
                i += 2
                continue
            if src.startswith(in_s, i):
                i += len(in_s)
                in_s = None
                continue
            i += 1
            continue
        if src.startswith("'''", i) or src.startswith('"""', i):
            in_s = src[i:i + 3]
            i += 3
            continue
        if c in "'\"":
            in_s = c
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def match_paren(src, open_idx):
    depth, i, n, in_s = 0, open_idx, len(src), None
    while i < n:
        c = src[i]
        if in_s:
            if c == "\\":
                i += 2
                continue
            if src.startswith(in_s, i):
                i += len(in_s)
                in_s = None
                continue
            i += 1
            continue
        if src.startswith("'''", i) or src.startswith('"""', i):
            in_s = src[i:i + 3]
            i += 3
            continue
        if c in "'\"":
            in_s = c
            i += 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1


def split_args(body):
    args, depth, cur, i, n, in_s = [], 0, [], 0, len(body), None
    while i < n:
        c = body[i]
        if in_s:
            cur.append(c)
            if c == "\\" and i + 1 < n:
                cur.append(body[i + 1])
                i += 2
                continue
            if body.startswith(in_s, i):
                in_s = None
            i += 1
            continue
        if body.startswith("'''", i) or body.startswith('"""', i):
            in_s = body[i:i + 3]
            cur.append(in_s)
            i += 3
            continue
        if c in "'\"":
            in_s = c
            cur.append(c)
            i += 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            args.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    if "".join(cur).strip():
        args.append("".join(cur))
    return args


def named(args):
    out = {}
    for a in args:
        m = re.match(r"\s*([a-z_][A-Za-z0-9_]*)\s*:(.*)", a, re.S)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def calls(src):
    for m in IDENT.finditer(src):
        op = m.end() - 1
        close = match_paren(src, op)
        if close < 0:
            continue
        yield m.group(1), m.start(), src[op + 1:close - 1]


def line_of(src, idx):
    return src.count("\n", 0, idx) + 1


def num(v):
    m = re.fullmatch(r"(\d+(?:\.\d+)?)", (v or "").strip())
    return float(m.group(1)) if m else None


def font_sizes(sub):
    out = [float(x) for x in re.findall(r"fontSize\s*:\s*(\d+(?:\.\d+)?)", sub)]
    for m in re.finditer(r"AppTextStyles\.([A-Za-z]+)", sub):
        if m.group(1) in STYLE_SIZES:
            out.append(float(STYLE_SIZES[m.group(1)]))
    return out


def check_bursting_text(src):
    """Fixed-height boxes whose own text subtree cannot fit at 2.0x."""
    hits = []
    for name, start, body in calls(src):
        if name not in BOXES:
            continue
        a = named(split_args(body))
        h = num(a.get("height"))
        if h is None or h > 120:
            continue
        sub = a.get("child", "") or a.get("children", "")
        # A spacer has no child at all. Excluding it structurally, rather than
        # by lookahead, is the single biggest source of noise removed.
        if not sub or not re.search(r"\bText\s*\(", sub):
            continue
        if "FittedBox" in sub or "textScaler" in sub or "textScaler" in body:
            continue
        sizes = font_sizes(sub)
        if not sizes:
            continue
        vpad = 0.0
        for m in re.finditer(r"vertical\s*:\s*(\d+(?:\.\d+)?)", sub):
            vpad = max(vpad, float(m.group(1)) * 2)
        for m in re.finditer(r"EdgeInsets\.all\s*\(\s*(\d+(?:\.\d+)?)", sub):
            vpad = max(vpad, float(m.group(1)) * 2)
        f = max(sizes)
        line_box = 1.0 if "textHeightBehavior" in sub else 1.2
        ml = re.search(r"maxLines\s*:\s*(\d+)", sub)
        lines = int(ml.group(1)) if ml else 1
        budget = h - vpad
        need = f * MAX_SCALE * line_box * lines
        if need > budget:
            burst = budget / (f * line_box * lines)
            if burst < MAX_SCALE:
                hits.append((line_of(src, start),
                             f"{name}(height: {h:g}) holds {f:g}px text x{lines}: "
                             f"needs {need:.1f}px at {MAX_SCALE}x, has {budget:g}px "
                             f"-> bursts at {burst:.2f}x"))
    return hits


def check_touch_targets(src):
    """Gesture wrappers around a box under the 48dp floor."""
    hits = []
    for name, start, body in calls(src):
        if name not in TAPPABLE:
            continue
        a = named(split_args(body))
        if not any(k in a for k in ("onTap", "onLongPress", "onTapDown", "onPressed")):
            continue
        child = a.get("child", "").strip()
        cm = IDENT.match(child)
        if not cm or cm.group(1) not in BOXES:
            continue
        op = child.index("(", cm.start(1))
        close = match_paren(child, op)
        if close < 0:
            continue
        ca = named(split_args(child[op + 1:close - 1]))
        dims = [d for d in (num(ca.get("width")), num(ca.get("height"))) if d is not None]
        if dims and max(dims) < TOUCH_FLOOR:
            hits.append((line_of(src, start),
                         f"{name} -> {cm.group(1)}({'x'.join(f'{d:g}' for d in dims)}) "
                         f"under the {TOUCH_FLOOR:g}dp floor"))
    return hits


def check_perpetual_animation(src, rel):
    """A never-ending animation in an always-mounted widget, with no own layer.

    THIS IS A PERFORMANCE BUG THAT LOOKS LIKE NOTHING. A ticker schedules a
    frame every vsync, and a BackdropFilter re-runs its blur on every frame it
    takes part in. This app's shell stacks three of them, so ONE perpetual
    animation anywhere in the shell turns every blur in the app into a 60fps
    full-framebuffer readback -- on every screen, forever, whether or not the
    animating pixel is even visible.

    All three known cases were exactly this:
      * GlowingAvatar, in a drawer app_shell never unmounts (fixed with
        TickerMode, so the closed drawer costs nothing).
      * the SOS button's pulse, mounted by SosGate on every route.
      * the app bar's unread badge, likewise on every route.

    Measured with the drawer case live: `dumpsys gfxinfo` reported high input
    latency on 114 of 117 frames while rendering stayed at a 5ms 50th
    percentile and 0.00% jank. Nothing looked slow; touches simply arrived
    late. Neither `flutter analyze` nor a rendering profile flags it.

    So: a `.repeat(` inside the shell must be paired with a RepaintBoundary
    (its own layer, so its repaints stop at its own bounds) and must honour
    reduced motion. Checked per FILE rather than per widget -- a coarser test
    than ideal, but it fails loudly on a new unisolated shell animation, which
    is the case that matters.
    """
    # Only the always-mounted surfaces. A screen's own animation unmounts with
    # the screen and cannot cost anything on other routes.
    SHELL = ("features/shell/", "shared/widgets/glass_bottom_nav",
             "shared/widgets/profile_identity_header", "features/sos/presentation/sos_floating_button")
    if not any(s in rel for s in SHELL):
        return []
    hits = []
    for m in re.finditer(r"\.repeat\s*\(|repeat\s*\(\s*reverse", src):
        line = line_of(src, m.start())
        if "RepaintBoundary" not in src:
            hits.append((line, "perpetual animation in an always-mounted shell "
                               "widget with no RepaintBoundary in the file"))
        if "isReduced" not in src and "disableAnimations" not in src:
            hits.append((line, "perpetual animation in the shell that never "
                               "checks reduced motion"))
    return hits


def check_shrunk_buttons(src):
    """Material buttons whose 48dp default has been explicitly shrunk."""
    hits = []
    for name, start, body in calls(src):
        if name not in MATERIAL_BUTTONS:
            continue
        a = named(split_args(body))
        mins = [num(x) for x in re.findall(r"min(?:Width|Height)\s*:\s*([\d.]+)",
                                           a.get("constraints", ""))]
        mins = [m for m in mins if m is not None]
        if mins and min(mins) < TOUCH_FLOOR:
            hits.append((line_of(src, start),
                         f"{name} constraints shrunk to {min(mins):g}dp "
                         f"(floor is {TOUCH_FLOOR:g})"))
        elif "MaterialTapTargetSize.shrinkWrap" in body:
            hits.append((line_of(src, start), f"{name} uses tapTargetSize: shrinkWrap"))
    return hits


CHECKS = [
    ("text bursts its box", check_bursting_text),
    ("touch target under 48dp", check_touch_targets),
    ("button tap target shrunk", check_shrunk_buttons),
]

SELFTESTS = [
    ("a border width is not a touch target", check_touch_targets,
     "GestureDetector(onTap: f, child: Container(width: 200, "
     "decoration: BoxDecoration(border: Border.all(width: 0.5))))", False),
    ("a 24dp tappable is a finding", check_touch_targets,
     "GestureDetector(onTap: f, child: SizedBox(width: 24, height: 24, child: Icon(i)))", True),
    ("a 48dp tappable is fine", check_touch_targets,
     "GestureDetector(onTap: f, child: SizedBox(width: 48, height: 48, child: Icon(i)))", False),
    ("no handler means not a control", check_touch_targets,
     "GestureDetector(child: SizedBox(width: 10, height: 10))", False),
    ("a spacer is not a text box", check_bursting_text,
     "SizedBox(height: 24), Text('hello')", False),
    ("a 44dp box with 22px text bursts", check_bursting_text,
     "Container(height: 44, child: Text('A', style: TextStyle(fontSize: 22)))", True),
    ("FittedBox rescues it", check_bursting_text,
     "Container(height: 44, child: FittedBox(child: Text('A', "
     "style: TextStyle(fontSize: 22))))", False),
    ("a theme role is resolved too", check_bursting_text,
     "Container(height: 20, child: Text('x', style: AppTextStyles.headlineLarge))", True),
    ("a roomy box is fine", check_bursting_text,
     "Container(height: 60, child: Text('x', style: TextStyle(fontSize: 11)))", False),
    ("shrunk constraints are a finding", check_shrunk_buttons,
     "IconButton(constraints: BoxConstraints(minWidth: 32, minHeight: 32), icon: Icon(x))", True),
    ("a default IconButton is fine", check_shrunk_buttons,
     "IconButton(icon: Icon(x), onPressed: f)", False),
]


PERPETUAL_SELFTESTS = [
    # The exact shape the SOS button shipped with: repeats forever, no layer,
    # no reduced-motion check, on a route-independent shell widget.
    ("an unisolated shell animation is a finding",
     "features/sos/presentation/sos_floating_button.dart",
     "Container().animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.06)",
     True),
    ("isolated + reduced-motion-aware is fine",
     "features/sos/presentation/sos_floating_button.dart",
     "RepaintBoundary(child: Container().animate(onPlay: (c) "
     "{ if (!AppMotion.isReduced(context)) c.repeat(reverse: true); }))",
     False),
    # A screen's own animation unmounts with the screen, so it cannot cost
    # anything on other routes and is not this check's business.
    ("a screen-local animation is not this check's business",
     "features/transport/presentation/transport_screen.dart",
     "_c.repeat(reverse: true);",
     False),
]


def selftest(verbose=True):
    ok = True
    for label, rel, sample, expect in PERPETUAL_SELFTESTS:
        got = bool(check_perpetual_animation(strip_comments(sample), rel))
        if got != expect:
            print(f"  FAIL {label}: expected {expect}, got {got}")
            ok = False
        elif verbose:
            print(f"  pass {label}")
    for label, fn, sample, expect in SELFTESTS:
        got = bool(fn(strip_comments(sample)))
        if got != expect:
            print(f"  FAIL {label}: expected {expect}, got {got}")
            ok = False
        elif verbose:
            print(f"  pass {label}")
    s = "a\n// c\n/* x\ny */\nb"
    if len(strip_comments(s)) != len(s) or strip_comments(s).count("\n") != s.count("\n"):
        print("  FAIL comment stripping moved character positions")
        ok = False
    elif verbose:
        print("  pass comment stripping preserves positions")
    return ok


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    lib = os.path.abspath(os.path.join(here, "..", "..", "lib"))
    if "--lib" in sys.argv:
        lib = os.path.abspath(sys.argv[sys.argv.index("--lib") + 1])

    print("self-tests:")
    if not selftest():
        print("\nself-tests failed -- refusing to report findings")
        sys.exit(2)

    findings, scanned = [], 0
    for root, _, names in os.walk(lib):
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            p = os.path.join(root, n)
            scanned += 1
            src = strip_comments(open(p, encoding="utf-8", errors="replace").read())
            rel = os.path.relpath(p, lib).replace("\\", "/")
            for label, fn in CHECKS:
                for line, msg in fn(src):
                    if f"lib/{rel}:{line}" in ALLOW:
                        continue
                    findings.append(f"lib/{rel}:{line}  [{label}]  {msg}")
            # Needs the path as well as the source, so it is called separately.
            for line, msg in check_perpetual_animation(src, rel):
                if f"lib/{rel}:{line}" in ALLOW:
                    continue
                findings.append(f"lib/{rel}:{line}  [perpetual animation]  {msg}")

    print(f"\nscanned {scanned} dart files under lib/")
    if not findings:
        print("no UI bounds violations: every fixed box survives "
              f"{MAX_SCALE}x text, every control meets {TOUCH_FLOOR:g}dp")
        return
    print(f"\n{len(findings)} UI bounds violation(s):\n")
    for f in findings:
        print("  " + f)
    print("\nFix by scaling the box with MediaQuery.textScalerOf when the text "
          "must stay readable,\nor FittedBox(fit: BoxFit.scaleDown) when the box "
          "is a fixed geometric element.\nA genuine exception goes in ALLOW with "
          "a reason.")
    sys.exit(1)


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(0 if selftest() else 1)
    main()
