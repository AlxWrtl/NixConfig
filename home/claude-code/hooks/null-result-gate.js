#!/usr/bin/env node
let input = "";
// Without an explicit encoding, a multi-byte character straddling a 64 KiB
// chunk boundary is silently replaced by U+FFFD. The messages below are
// French and every accent is two bytes.
process.stdin.setEncoding("utf8");
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);

    // Scope guard. This list must stay EQUAL, in BOTH directions, to the
    // PostToolUse matcher registered for this hook in settings.nix.
    // FAIL-CLOSED: a payload with no `tool_name` is not classified at all.
    const TOOLS = ["mcp__claude-in-chrome__javascript_tool","mcp__playwright__browser_evaluate","mcp__playwright__browser_run_code_unsafe"];
    if (typeof data.tool_name !== "string" || TOOLS.indexOf(data.tool_name) === -1) process.exit(0);

    // Verdicts: only "NULL" fires trigger A. "NON_NULL" and "UNREADABLE"
    // never do — an unreadable shape is not evidence of absence.

    // An MCP content part. A text part must really carry text; a non-text
    // part (image, resource) carries none.
    function isPart(p) {
      return p !== null && typeof p === "object" && !Array.isArray(p)
        && typeof p.type === "string"
        && (p.type !== "text" || typeof p.text === "string");
    }

    // Shared by the BARE parts array and the {content:[…]} envelope — the
    // same payload, with and without its wrapper.
    function readParts(parts, depth) {
      if (parts.length === 0) return "NULL";
      let text = "";
      let seenText = false;
      for (const part of parts) {
        if (part && part.type === "text" && typeof part.text === "string") {
          text += part.text;
          seenText = true;
        }
      }
      // No text part at all: image/resource only. UNREADABLE, never NULL.
      if (!seenText) return "UNREADABLE";
      return classify(text, depth + 1);
    }

    // The body of the FIRST `### …` section, or null when the string does
    // not open on one. A `###` further down is content, not a wrapper, and
    // the section stops at the next one — the real report carries a
    // `### Ran Playwright code` block after the value.
    function resultSection(s) {
      const m = /^###[^\n]*\n/.exec(s);
      if (m === null) return null;
      const body = s.slice(m[0].length);
      const cut = body.search(/\n###/);
      if (cut === -1) return body;
      return body.slice(0, cut);
    }

    // A zero is an absence only when the field it sits in COUNTS
    // something, so the key NAME is part of the test. Measured false
    // positives of the previous "every own value is 0" rung: {x:0,y:0}
    // (the origin), {errors:0,warnings:0} (a CLEAN console — a positive
    // finding reported as a broken instrument), {scrollY:0}. And a
    // non-numeric neighbour no longer disqualifies the record: a
    // {matched:0,total:0,selector:".promo"} is the same signature with a
    // label attached, and {result:{matched:0,total:0}} is it nested.
    const COUNTER_KEY = /^(n|count|total|matched|found|hits|results)$/i;
    function scanCounters(o, depth, acc) {
      if (depth > 2) return;
      for (const k of Object.keys(o)) {
        const n = o[k];
        if (typeof n === "number") {
          if (!Number.isFinite(n)) continue;
          acc.numeric += 1;
          if (n !== 0) acc.allZero = false;
          if (COUNTER_KEY.test(k)) acc.counter = true;
        } else if (n !== null && typeof n === "object" && !Array.isArray(n)) {
          scanCounters(n, depth + 1, acc);
        }
      }
    }
    function allZeroCounters(o) {
      const acc = { numeric: 0, counter: false, allZero: true };
      scanCounters(o, 0, acc);
      return acc.numeric > 0 && acc.counter && acc.allZero;
    }

    function classify(v, depth) {
      // Bounded. A report wrapping a report wrapping a report is not a
      // measurement: stop reading and stay silent.
      if (depth > 5) return "UNREADABLE";
      // R1 — nothing at all.
      if (v === null || v === undefined) return "NULL";
      // R2 — string.
      if (typeof v === "string") {
        const sect = resultSection(v);
        const s = (sect === null ? v : sect).trim();
        if (s === "") return "NULL";
        // A crash is not an absence. The two real errors in the corpus
        // arrive as `Error: ### Error\n…` and used to survive by accident.
        if (/^error\b/i.test(s)) return "UNREADABLE";
        // The section body is the probe's RETURN VALUE, JSON-serialised.
        // Classify the value, never its rendering: this is what tells
        // `"0"` from `"sombre"` and `[]` from `[1,2,3]`.
        let parsed = null;
        let parsedOk = false;
        try { parsed = JSON.parse(s); parsedOk = true; } catch (e) { parsedOk = false; }
        if (parsedOk) return classify(parsed, depth + 1);
        // `none` and `not found` are deliberately ABSENT from this list:
        // `getComputedStyle(el).display === "none"` is the commonest
        // browser measurement there is and it is DECIDED (the element is
        // hidden), and a page title of "Not Found" means the 404 IS the
        // answer. They describe a measured state, not an absence.
        const NULLISH = "0|\\[\\]|\\{\\}|null|undefined";
        const NULLISH_EXTRA = "";
        if (new RegExp("^(" + NULLISH + NULLISH_EXTRA + ")$", "i").test(s)) return "NULL";
        if (/^no (matches|results|hits)\b/i.test(s)) return "NULL";
        return "NON_NULL"; // rung R2
      }
      // R3 — number.
      if (typeof v === "number") {
        if (Number.isNaN(v)) return "UNREADABLE";
        if (v === 0) return "NULL";
        return "NON_NULL"; // rung R3
      }
      // R4 — boolean. DELIBERATE exclusion: a boolean is a decided answer,
      // not an absence. `false` must never be read as a null result.
      if (typeof v === "boolean") return "NON_NULL";
      // R5 — array.
      if (Array.isArray(v)) {
        if (v.length === 0) return "NULL";
        // A BARE parts array is R6's payload with the wrapper stripped,
        // and it is what 188 of 190 measured calls actually return.
        // Reading it as "a non-empty array, therefore an answer" is what
        // made this gate mute on 100 % of its traffic. An array whose
        // elements are not parts stays NON_NULL; a parts array carrying no
        // text part stays UNREADABLE.
        if (v.every(isPart)) return readParts(v, depth);
        return "NON_NULL"; // rung R5
      }
      if (typeof v === "object") {
        // An ERROR is not an absence. Announcing "Résultat NUL" for a
        // probe that crashed is, word for word, the fault this hook exists
        // to correct.
        if (v.isError === true) return "UNREADABLE";
        // R6 — the documented MCP envelope: { content: [ { type, text } ] }.
        // Never seen in the local corpus; kept so the gate does not go
        // mute again the day it starts arriving.
        if (Array.isArray(v.content)) return readParts(v.content, depth);
        const keys = Object.keys(v);
        // R7 — object with no own key.
        if (keys.length === 0) return "NULL";
        // R8 — the `{matched:0,total:0}` signature, and only that.
        if (allZeroCounters(v)) return "NULL";
        // R9 — any other object.
        return "NON_NULL"; // rung R9
      }
      return "UNREADABLE";
    }

    // R0 — the key itself is absent. Nothing was measured, so nothing is
    // null: UNREADABLE, and the hook stays silent.
    const verdict = Object.prototype.hasOwnProperty.call(data, "tool_response")
      ? classify(data.tool_response, 0)
      : "UNREADABLE";

    // Trigger B reads the probe SOURCE without assuming a field name: the
    // three tools disagree on it. MEASURED over the same 190 calls:
    // browser_evaluate carries `function` (188/188), javascript_tool
    // carries `action`/`tabId`/`text` and the source is in `text` (2/2),
    // browser_run_code_unsafe carries `code`.
    let source = null;
    const ti = data.tool_input;
    if (ti && typeof ti === "object") {
      const FIELDS = ["code", "function", "script", "expression", "text"];
      for (const f of FIELDS) {
        if (typeof ti[f] !== "undefined") { source = String(ti[f]); break; }
      }
      if (source === null) {
        try { source = JSON.stringify(ti); } catch (e) { source = null; }
      }
      // ONE bound, on BOTH branches. The previous version capped the
      // fallback at 20 000 characters and left the named-field branch —
      // the only one that runs in production — unbounded: it lost
      // detections exactly where it applied, and protected nothing where
      // it did not.
      const SOURCE_CAP = 1000000;
      if (typeof source === "string" && source.length > SOURCE_CAP) {
        source = source.slice(0, SOURCE_CAP);
      }
    }

    // The idiom must sit in a PROPERTY-ACCESS position. MEASURED false
    // positives of a bare /\boffsetParent\b/: an avoidance comment
    // ("NOT using offsetParent: null for position:fixed"), a string
    // literal (document.title === 'offsetParent tutorial'), a selector
    // ([data-test="offsetParent-demo"]). Scolding a probe that has ALREADY
    // applied the advice is the guard punishing good practice.
    // IRREDUCIBLE and accepted as such: 'offset' + 'Parent' is not caught.
    // A source-text matcher cannot see through concatenation and nothing
    // here pretends to.
    // Extensible: one entry today, the shape takes more.
    const ACCESS = "(?:\\.|\\[\\s*[\"'])";
    const BROKEN = [
      {
        re: new RegExp(ACCESS + "offsetParent\\b"),
        msg: "`offsetParent` est nul pour tout élément `position: fixed` : cette sonde "
          + "sous-compte et peut rendre 0 sur une page pleine de correspondances. Le "
          + "test natif est `el.checkVisibility({checkOpacity:true, checkVisibilityCSS:true})` "
          + "plus `getBoundingClientRect()`."
      }
    ];

    const msgs = [];
    if (verdict === "NULL") {
      msgs.push(
        "Résultat NUL. Un nul n'est pas un constat tant que l'instrument n'a pas rendu "
        + "du positif sur un cas qui DOIT matcher. Avant de le rapporter : exhiber le "
        + "dénominateur (combien ont été scannés), ou relancer la sonde sur un cas qui "
        + "doit matcher. `matched: 0, total: 0` est un instrument cassé, pas un constat."
      );
    }
    if (typeof source === "string" && source.length > 0) {
      for (const b of BROKEN) if (b.re.test(source)) msgs.push(b.msg); // trigger B
    }

    if (msgs.length === 0) process.exit(0);

    // Only the nested form carrying hookEventName is documented.
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: msgs.join(" ")
      }
    }));
  } catch (e) {}
  // NOT process.exit: an exit right after a write truncates on a pipe past
  // ~64 KiB. The message is 389 bytes today; setting the code and letting
  // the loop drain keeps that harmless if it ever grows.
  process.exitCode = 0;
});
