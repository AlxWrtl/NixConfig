#!/usr/bin/env bash
# Positive control for `hookNullResultGate` — the PostToolUse hook that tells
# the model a browser probe came back NULL.
#
# WHY THIS FILE WAS REBUILT. Its first version scored 33/33 while the hook it
# graded was mute on 190 of 190 real calls. Every fixture had been written to
# match the shapes the hook was coded for, so the suite proved only that the
# code agreed with itself. The fixtures below are REPLAYED from 190 recorded
# `mcp__playwright__browser_evaluate` / `javascript_tool` responses found in
# 717 local transcripts:
#
#   - `tool_response` is a BARE parts array `[{type:"text",text:"…"}]` in
#     188/190 cases, a bare string in 2/190. The documented `{content:[…]}`
#     envelope: 0/190. It is kept under test anyway — nothing guarantees it
#     will never arrive — but it is no longer the only shape asserted.
#   - the text it carries is a markdown REPORT, not a value:
#     `### Result\n<json>\n### Ran Playwright code\n```js…` in 186/190.
#
# Cases named `real-*` carry values taken verbatim from that corpus (`[]`,
# `""`, `"0"`, `{"n":0,"sample":[]}`, `"ok"`, `{"ligneTrouvee":false}`,
# `{"active":"hdr2","scrollTop":0}`, the `Error: ### Error` string).
#
# WHY EVERY RUNG IS ASSERTED IN BOTH POLARITIES. The hook renders THREE
# internal verdicts and only one of them may speak. NULL writes a JSON object
# on stdout. NON_NULL is silent. UNREADABLE is silent TOO — and that third
# verdict is the whole point: a shape the hook cannot read is not evidence of
# absence, and a hook that says "résultat nul" because it failed to parse its
# own input has invented a finding. A correction that makes everything bite is
# a failure, not a success, so each widening has a polarity partner here:
# `real-bare-array-empty` bites, `real-bare-array-list` must not;
# `h1-zero-labelled` bites, `h1-clean-console` must not.
#
# WHY THE UNREADABLE CASES ARE ASSERTED ON EMPTINESS. `malformed-json`,
# `empty-stdin`, `field-absent`, `mcp-content-nontext`, `bare-array-nontext`
# and `real-error-string` assert that stdout is empty byte for byte — never
# that some keyword is absent from it. An assertion on a missing word passes
# just as well when the hook crashed before printing anything, which is the
# failure it is supposed to catch.
#
# WHY THE WIRING CASES EXIST. A hook that is written, correct and never
# registered scores a perfect green here while doing nothing at all. The
# `wired-*`, `matcher-agrees` and `not-async` cases are the inertia detector:
# they read home/claude-code.nix and home/claude-code/settings.nix, and
# `matcher-agrees` compares the settings matcher against the hook's own `TOOLS`
# constant in BOTH directions, because a name present on one side only is a
# tool that either never reaches the hook or that the hook silently ignores.
#
# WHY THE MUTANTS ARE PART OF THE FILE. A test you have only ever seen PASS has
# not been run. Every runtime case below is reddened by at least one declared
# mutant, and each mutant must go red on EXACTLY its declared set — not simply
# "go red". A mutant that reddens every runtime case says the harness is
# coupled to the hook's structure, not that the hook is broken; that verdict is
# printed as a result about the probe, not swallowed.
#
#   m1  every nullity rung neutralised (classify never returns NULL).
#   m2  UNREADABLE returned as NULL, including the parse-failure path. This is
#       the mutant that matters most: it replays, verbatim, the fault this hook
#       corrects.
#   m3  the counter rung neutralised.
#   m4  the boolean rung read as an absence.
#   m5  the idiom word boundary removed.
#   m6  R9 (any other object) read as an absence.
#   m7  the scope guard removed.
#   m8  the counter-NAME gate removed (any all-zero record fires).
#   m9  `none` / `not found` put back in the nullish alternation.
#   m10 the `isError` guard removed.
#   m11 the idiom property-access requirement removed.
#   m12 the source cap lowered back to 20 000 characters.
#   m13 the bare-parts-array branch removed (the C1 short-circuit restored).
#   m14 the `### Result` section extraction removed.
#   m15 R3 (non-zero number) read as an absence.
#   m16 R2 (non-null string) read as an absence.
#   m17 R5 (non-empty non-parts array) read as an absence.
#   m18 trigger B (the broken-idiom rung) removed.
#
# ONE ACCEPTED BLIND SPOT, named so it cannot be mistaken for coverage:
# `idiom-concatenated-known-miss` asserts that `'offset' + 'Parent'` is NOT
# caught. A source-text matcher cannot see through concatenation; the case
# records the limit instead of pretending it is covered.
#
# THE EXACT COMMANDS THAT MAKE THIS PROBE GO RED:
#
#   bash checks/null-result-gate-probe.sh --mutants     # all of them, graded
#   bash checks/null-result-gate-probe.sh --mutant m2   # one, raw red output
#
# Standalone, like checks/codex-hooks-probe.sh and checks/scrapling-shim-fuzz.sh:
# NOT wired into `nix flake check`, because it shells out to `nix eval` to lift
# the hook body out of hooks.nix.
#
# usage: null-result-gate-probe.sh [hook.js]
#        null-result-gate-probe.sh --mutants
#        null-result-gate-probe.sh --mutant m1..m18
#
#        With no argument the hook body is extracted from the repository
#        source. Pass a path to grade a mutated copy instead.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$REPO_ROOT/checks/$(basename "${BASH_SOURCE[0]}")"

ALL_MUTANTS="m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 m16 m17 m18"

MODE="run"
ONE_MUTANT=""
case "${1:-}" in
  --mutants)
    MODE="mutants"
    shift
    ;;
  --mutant)
    MODE="one-mutant"
    ONE_MUTANT="${2:-}"
    case " $ALL_MUTANTS " in
      *" $ONE_MUTANT "*) ;;
      *)
        echo "probe: --mutant takes one of: $ALL_MUTANTS" >&2
        exit 2
        ;;
    esac
    shift 2 || true
    ;;
esac

SUT="${1:-}"

abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$PWD/$1" ;; esac; }

# --- work directory -----------------------------------------------------------
#
# An empty $WORK must STOP the run: every path would resolve to the filesystem
# root and the failures reported would all be the harness's own.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/null-result-gate-probe.XXXXXX") || {
  echo "probe: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  echo "probe: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
trap 'if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf "$WORK"; fi' EXIT

# Never write into, or grade, this repository by accident.
case "$WORK/" in
  "$REPO_ROOT"/*)
    echo "probe: the work directory is inside this repository — refusing to run" >&2
    exit 2
    ;;
esac

mkdir -p "$WORK/out"

# --- interpreters -------------------------------------------------------------

NODE="$(command -v node 2> /dev/null || true)"
[ -n "$NODE" ] || NODE=/run/current-system/sw/bin/node
[ -x "$NODE" ] || {
  echo "probe: no usable node interpreter (tried \$PATH and /run/current-system/sw/bin/node)" >&2
  exit 2
}
JQ="$(command -v jq 2> /dev/null || true)"
[ -n "$JQ" ] || {
  echo "probe: jq not found — the payload builders and stdout assertions need it" >&2
  exit 2
}

# --- the script under test ----------------------------------------------------

HOOKS_NIX="$REPO_ROOT/home/claude-code/hooks.nix"
CLAUDE_NIX="$REPO_ROOT/home/claude-code.nix"
SETTINGS_NIX="$REPO_ROOT/home/claude-code/settings.nix"
for f in "$HOOKS_NIX" "$CLAUDE_NIX" "$SETTINGS_NIX"; do
  [ -r "$f" ] || {
    echo "probe: cannot read $f" >&2
    exit 2
  }
done

extract_hook() { # extract_hook <destination>
  local dest="$1" nix
  nix="$(command -v nix 2> /dev/null || true)"
  [ -n "$nix" ] || {
    echo "probe: \`nix\` not found and no hook path was given — nothing to grade" >&2
    exit 2
  }
  "$nix" eval --raw --impure --expr \
    "(import \"$HOOKS_NIX\" { graphifyReindexPkg = \"/nix/store/x\"; vaultSnapshotPkg = \"/nix/store/y\"; }).hookNullResultGate" \
    > "$dest" 2> "$WORK/extract.err" || {
    echo "probe: extracting hookNullResultGate from hooks.nix failed" >&2
    head -c 800 "$WORK/extract.err" >&2
    exit 2
  }
  [ -s "$dest" ] || {
    echo "probe: the extracted hook body is empty — refusing to report" >&2
    exit 2
  }
}

ORIG="$WORK/null-result-gate.js"
if [ -n "$SUT" ]; then
  SUT="$(abspath "$SUT")"
  [ -f "$SUT" ] && [ -r "$SUT" ] || {
    echo "probe: script under test not found or not readable: $SUT" >&2
    exit 2
  }
else
  extract_hook "$ORIG"
  SUT="$ORIG"
fi

# ==============================================================================
# MUTANT DRIVER
# ==============================================================================
#
# Runs when this script is invoked with --mutants or --mutant. Each mutant is
# built with `sed` from the REAL hook body into $WORK, syntax-checked, proven
# to differ from the original, then graded by re-running this same script
# against it. Nothing is ever written into the repository.
#
# The runtime-case count is NOT a constant here: it is read back from the
# child run, which derives it from the case table itself. A hand-maintained
# count silently disables the "coupled harness" branch the first time someone
# adds a case and forgets to bump it.

M1_EXPECT="all-zero-record empty-array empty-object empty-string h1-zero-labelled h1-zero-nested header-empty-after-strip idiom-and-null mcp-content-empty mcp-content-empty-text mcp-content-zero no-matches-phrase null-literal real-bare-array-counter-zero real-bare-array-empty real-bare-array-emptystr real-bare-array-null real-bare-array-quoted-zero real-bare-array-zero real-bare-string-zero regression-bare-array-not-a-list regression-header-prefix regression-trailing-section run-code-unsafe-in-scope whitespace-string zero-number zero-string"
M2_EXPECT="bare-array-nontext empty-stdin field-absent h3-mcp-iserror malformed-json mcp-content-nontext real-error-string"
M3_EXPECT="all-zero-record h1-zero-labelled h1-zero-nested real-bare-array-counter-zero"
M4_EXPECT="boolean-false boolean-true idiom-concatenated-known-miss idiom-in-avoidance-comment idiom-in-selector-string idiom-in-string-literal idiom-lookalike idiom-only-nonnull"
M5_EXPECT="idiom-lookalike"
M6_EXPECT="h1-clean-console h1-negzero h1-origin-coords h1-scroll-top mixed-zero-record object-with-keys real-bare-array-false real-bare-array-scrolltop"
M7_EXPECT="tool-name-absent wrong-tool"
M8_EXPECT="h1-clean-console h1-negzero h1-origin-coords h1-scroll-top real-bare-array-scrolltop"
M9_EXPECT="h2-real-computed-display h2-str-none h2-str-notfound"
M10_EXPECT="h3-mcp-iserror"
M11_EXPECT="idiom-in-avoidance-comment idiom-in-selector-string idiom-in-string-literal"
M12_EXPECT="idiom-beyond-20000-fallback idiom-beyond-20000-known-field"
M13_EXPECT="real-bare-array-counter-zero real-bare-array-empty real-bare-array-emptystr real-bare-array-null real-bare-array-quoted-zero real-bare-array-zero regression-bare-array-not-a-list"
M14_EXPECT="header-empty-after-strip real-bare-array-counter-zero real-bare-array-empty real-bare-array-emptystr real-bare-array-null real-bare-array-quoted-zero real-bare-array-zero real-bare-string-zero regression-header-prefix regression-trailing-section"
M15_EXPECT="nonzero-number real-bare-array-42"
M16_EXPECT="h2-real-computed-display h2-str-none h2-str-notfound header-mid-string header-only-no-newline mcp-content-text nonempty-string real-bare-array-ok"
M17_EXPECT="array-of-plain-objects nonempty-array real-bare-array-list"
M18_EXPECT="idiom-and-null idiom-beyond-20000-fallback idiom-beyond-20000-known-field idiom-bracket-access idiom-chrome-text idiom-only-nonnull"

mutant_expect() { # mutant_expect <mN>
  local v
  v="$(printf '%s' "$1" | tr 'a-z' 'A-Z')_EXPECT"
  printf '%s\n' "${!v}"
}

build_mutant() { # build_mutant <mN> <destination>
  local which="$1" dest="$2" anchor=""
  case "$which" in
    m1)
      # Every nullity rung inside classify() neutralised. The final
      # `verdict === "NULL"` test is deliberately left intact, so the mutation
      # is in the CLASSIFIER, not in the trigger that reads it.
      sed -e 's/return "NULL";/return "NON_NULL";/g' "$ORIG" > "$dest"
      anchor='if (s === "") return "NON_NULL";'
      ;;
    m2)
      # UNREADABLE reported as NULL. The empty `catch` is filled too: a hook
      # that cannot parse its input is UNREADABLE by the same doctrine, and
      # leaving the catch alone would exempt the two cases that matter most.
      sed -e 's/return "UNREADABLE";/return "NULL";/g' \
        -e 's/: "UNREADABLE";/: "NULL";/g' \
        -e 's|} catch (e) {}|} catch (e) { process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"Resultat NUL (mutant m2)."}})); }|' \
        "$ORIG" > "$dest"
      anchor='mutant m2'
      # The word also appears in the hook's own comments; only the VERDICTS
      # must be gone.
      if grep -qE 'return "UNREADABLE"|: "UNREADABLE";' "$dest"; then
        echo "probe: m2 left an UNREADABLE verdict behind — the anchor moved" >&2
        return 1
      fi
      ;;
    m3)
      sed -e 's,if (allZeroCounters(v)) return "NULL";,if (false) return "NULL";,' "$ORIG" > "$dest"
      anchor='if (false) return "NULL";'
      ;;
    m4)
      sed -e 's,if (typeof v === "boolean") return "NON_NULL";,if (typeof v === "boolean") return "NULL";,' "$ORIG" > "$dest"
      anchor='if (typeof v === "boolean") return "NULL";'
      ;;
    m5)
      sed -e 's,offsetParent\\\\b,offsetParent,' "$ORIG" > "$dest"
      anchor='new RegExp(ACCESS + "offsetParent")'
      ;;
    m6)
      sed -e 's,return "NON_NULL"; // rung R9,return "NULL"; // rung R9,' "$ORIG" > "$dest"
      anchor='return "NULL"; // rung R9'
      ;;
    m7)
      sed -e 's,if (typeof data.tool_name !== "string" || TOOLS.indexOf(data.tool_name) === -1) process.exit(0);,if (false) process.exit(0);,' "$ORIG" > "$dest"
      anchor='if (false) process.exit(0);'
      ;;
    m8)
      sed -e 's,const COUNTER_KEY = .*$,const COUNTER_KEY = /^/;,' "$ORIG" > "$dest"
      anchor='const COUNTER_KEY = /^/;'
      ;;
    m9)
      sed -e 's,const NULLISH_EXTRA = "";,const NULLISH_EXTRA = "|none|not found";,' "$ORIG" > "$dest"
      anchor='const NULLISH_EXTRA = "|none|not found";'
      ;;
    m10)
      sed -e 's,if (v.isError === true) return "UNREADABLE";,if (false) return "UNREADABLE";,' "$ORIG" > "$dest"
      anchor='if (false) return "UNREADABLE";'
      ;;
    m11)
      sed -e 's,const ACCESS = .*$,const ACCESS = "";,' "$ORIG" > "$dest"
      anchor='const ACCESS = "";'
      ;;
    m12)
      sed -e 's,const SOURCE_CAP = 1000000;,const SOURCE_CAP = 20000;,' "$ORIG" > "$dest"
      anchor='const SOURCE_CAP = 20000;'
      ;;
    m13)
      # `|` as the delimiter: the anchor itself contains a comma.
      sed -e 's|if (v.every(isPart)) return readParts(v, depth);|if (false) return readParts(v, depth);|' "$ORIG" > "$dest"
      anchor='if (false) return readParts(v, depth);'
      ;;
    m14)
      sed -e 's,const sect = resultSection(v);,const sect = null;,' "$ORIG" > "$dest"
      anchor='const sect = null;'
      ;;
    m15)
      sed -e 's,return "NON_NULL"; // rung R3,return "NULL"; // rung R3,' "$ORIG" > "$dest"
      anchor='return "NULL"; // rung R3'
      ;;
    m16)
      sed -e 's,return "NON_NULL"; // rung R2,return "NULL"; // rung R2,' "$ORIG" > "$dest"
      anchor='return "NULL"; // rung R2'
      ;;
    m17)
      sed -e 's,return "NON_NULL"; // rung R5,return "NULL"; // rung R5,' "$ORIG" > "$dest"
      anchor='return "NULL"; // rung R5'
      ;;
    m18)
      sed -e 's,for (const b of BROKEN) if (b.re.test(source)) msgs.push(b.msg); // trigger B,;,' "$ORIG" > "$dest"
      anchor='BROKEN'
      if grep -q 'b.re.test(source)' "$dest"; then
        echo "probe: m18 left trigger B in place — the anchor moved" >&2
        return 1
      fi
      ;;
  esac
  if [ -n "$anchor" ] && ! grep -qF "$anchor" "$dest"; then
    echo "probe: $which did not apply — the anchor moved (looked for: $anchor)" >&2
    return 1
  fi
  if cmp -s "$ORIG" "$dest"; then
    echo "probe: $which is byte-identical to the original — a no-op mutant proves nothing" >&2
    return 1
  fi
  "$NODE" --check "$dest" 2> "$WORK/$which.syntax" || {
    echo "probe: $which is not valid JavaScript:" >&2
    head -c 400 "$WORK/$which.syntax" >&2
    return 1
  }
  return 0
}

if [ "$MODE" != "run" ]; then
  [ -f "$ORIG" ] || extract_hook "$ORIG"
  MUT_FAIL=0

  echo "=== null-result-gate mutants (built from the live hook, in $WORK) ==="
  echo

  # Baseline first. Grading a mutant against a suite that is not green to begin
  # with would attribute the harness's own failures to the mutation.
  set +e
  BASE_OUT="$("$SELF" "$ORIG" 2>&1)"
  BASE_RC=$?
  set -e
  BASE_RED="$(printf '%s\n' "$BASE_OUT" | awk '/^FAIL /{print $2}' | sort | tr '\n' ' ')"
  RUNTIME_CASES="$(printf '%s\n' "$BASE_OUT" | awk '/^runtime-cases: /{print $2; exit}')"
  if [ "$BASE_RC" -eq 0 ]; then
    echo "baseline: green — $(printf '%s\n' "$BASE_OUT" | grep -E '^=== [0-9]+ passed')"
  else
    echo "baseline: NOT GREEN (rc=$BASE_RC), red on: $BASE_RED"
    echo "baseline: refusing to grade mutants against a suite that already fails" >&2
    exit 2
  fi
  case "${RUNTIME_CASES:-}" in
    '' | *[!0-9]*)
      echo "probe: could not read the runtime-case count back from the child run" >&2
      exit 2
      ;;
  esac
  echo "baseline: $RUNTIME_CASES runtime cases, derived from the case table"
  echo

  for m in $ALL_MUTANTS; do
    [ "$MODE" = "one-mutant" ] && [ "$m" != "$ONE_MUTANT" ] && continue
    MF="$WORK/$m.js"
    if ! build_mutant "$m" "$MF"; then
      echo "MUTANT $m: COULD NOT BE BUILT"
      MUT_FAIL=$((MUT_FAIL + 1))
      continue
    fi
    set +e
    MOUT="$("$SELF" "$MF" 2>&1)"
    set -e
    RED="$(printf '%s\n' "$MOUT" | awk '/^FAIL /{print $2}' | sort | tr '\n' ' ')"
    RED="${RED% }"
    N_RED="$(printf '%s\n' "$MOUT" | awk '/^FAIL /{print $2}' | wc -l | tr -d ' ')"

    WANT="$(mutant_expect "$m")"
    WANT="$(printf '%s\n' $WANT | sort | tr '\n' ' ')"
    WANT="${WANT% }"

    if [ "$MODE" = "one-mutant" ]; then
      printf '%s\n' "$MOUT"
      echo
    fi

    echo "MUTANT $m"
    echo "  red   ($N_RED): $RED"
    echo "  want  : $WANT"
    if [ "$RED" = "$WANT" ]; then
      echo "  verdict: TARGETED — the probe goes red on exactly the declared set"
    else
      echo "  verdict: MISMATCH"
      MUT_FAIL=$((MUT_FAIL + 1))
    fi
    if [ "$N_RED" -ge "$RUNTIME_CASES" ]; then
      echo "  NOTE: this mutant reddens every runtime case — that is a COUPLED"
      echo "        harness reporting on itself, not a broken hook."
    fi
    echo
  done

  if [ "$MUT_FAIL" -eq 0 ]; then
    echo "=== mutants: all declared red sets matched ==="
  else
    echo "=== mutants: $MUT_FAIL mutant(s) did not match their declared red set ==="
  fi
  [ "$MUT_FAIL" -eq 0 ]
  exit $?
fi

# ==============================================================================
# PAYLOADS
# ==============================================================================

TOOL="mcp__playwright__browser_evaluate"
TOOL_CHROME="mcp__claude-in-chrome__javascript_tool"
TOOL_UNSAFE="mcp__playwright__browser_run_code_unsafe"

# MEASURED field names, one per tool: browser_evaluate carries `function`
# (188/188 real calls), javascript_tool carries action/tabId/`text` (2/2),
# browser_run_code_unsafe carries `code`. None of them carries the `code` field
# the first version of this probe used for its idiom fixtures.
BENIGN_INPUT='{"function":"() => document.title"}'
IDIOM_FN="{\"function\":\"() => [...document.querySelectorAll('a')].filter(e => e.offsetParent).length\"}"
IDIOM_CHROME_INPUT="{\"action\":\"execute\",\"tabId\":1,\"text\":\"[...document.querySelectorAll('a')].filter(e => e.offsetParent).length\"}"
IDIOM_BRACKET="{\"function\":\"() => [...document.querySelectorAll('a')].filter(e => e['offsetParent']).length\"}"
UNSAFE_INPUT="{\"code\":\"() => document.querySelectorAll('a').length\"}"
# Same substring, NOT a property access of that name. None may fire.
LOOKALIKE_INPUT="{\"function\":\"() => { const v = el.offsetParentish || window.offsetParentage; return v; }\"}"
IDIOM_COMMENT_INPUT="{\"function\":\"() => { /* NOT using offsetParent: null for position:fixed */ return [...document.querySelectorAll('a')].filter(e => e.checkVisibility({checkOpacity:true})).length; }\"}"
IDIOM_STRLIT_INPUT="{\"function\":\"() => document.title === 'offsetParent tutorial'\"}"
IDIOM_SELECTOR_INPUT="{\"function\":\"() => document.querySelectorAll('[data-test=\\\"offsetParent-demo\\\"]').length\"}"
# The accepted blind spot: a source-text matcher cannot see through this.
IDIOM_CONCAT_INPUT="{\"function\":\"() => { const k = 'offset' + 'Parent'; return [...document.querySelectorAll('a')].filter(e => e[k]).length; }\"}"

pay() { # pay <name> <raw-content>
  printf '%s' "$2" > "$WORK/pay-$1.json"
  printf '%s\n' "$WORK/pay-$1.json"
}

mk() { # mk <name> <tool> <tool_input json> <tool_response json>
  "$JQ" -n --arg tool "$2" --argjson ti "$3" --argjson tr "$4" \
    '{hook_event_name:"PostToolUse",tool_name:$tool,tool_input:$ti,tool_response:$tr}' \
    > "$WORK/pay-$1.json" || {
    echo "probe: could not build the payload for $1 — the fixture is not valid JSON" >&2
    exit 2
  }
  printf '%s\n' "$WORK/pay-$1.json"
}

resp() { # resp <name> <tool_response json> — benign input, playwright tool
  mk "$1" "$TOOL" "$BENIGN_INPUT" "$2"
}

# The REAL wrapper, reproduced: a `### Result` section carrying the JSON value,
# followed by the `### Ran Playwright code` block the server appends.
report() { # report <json-value-as-text>
  printf '### Result\n%s\n### Ran Playwright code\n```js\nawait page.evaluate(() => x);\n```' "$1"
}
jq_bare() { "$JQ" -n --arg t "$1" '[{type:"text",text:$t}]'; }
jq_env() { "$JQ" -n --arg t "$1" '{content:[{type:"text",text:$t}]}'; }
jq_str() { "$JQ" -n --arg t "$1" '$t'; }

# --- biting: the nullity rungs, plain values ----------------------------------
P_NULL_LITERAL=$(resp null-literal 'null')
P_EMPTY_STRING=$(resp empty-string '""')
P_WS_STRING=$(resp whitespace-string '"   \n\t  "')
P_ZERO_NUMBER=$(resp zero-number '0')
P_ZERO_STRING=$(resp zero-string '"0"')
P_EMPTY_ARRAY=$(resp empty-array '[]')
P_EMPTY_OBJECT=$(resp empty-object '{}')
P_NO_MATCHES=$(resp no-matches-phrase '"No matches found for selector .promo"')
P_ALL_ZERO=$(resp all-zero-record '{"matched":0,"total":0}')

# --- biting: REPLAYED shapes. 188/190 bare array, 2/190 bare string -----------
P_REAL_EMPTY=$(resp real-bare-array-empty "$(jq_bare "$(report '[]')")")
P_REAL_NULL=$(resp real-bare-array-null "$(jq_bare "$(report 'null')")")
P_REAL_ZERO=$(resp real-bare-array-zero "$(jq_bare "$(report '0')")")
P_REAL_EMPTYSTR=$(resp real-bare-array-emptystr "$(jq_bare "$(report '""')")")
P_REAL_QZERO=$(resp real-bare-array-quoted-zero "$(jq_bare "$(report '"0"')")")
P_REAL_COUNTER=$(resp real-bare-array-counter-zero "$(jq_bare "$(report '{
  "n": 0,
  "sample": []
}')")")
P_REAL_STR_ZERO=$(resp real-bare-string-zero "$(jq_str "$(report '0')")")

# --- biting: the documented envelope, kept although never observed ------------
P_MCP_EMPTY=$(resp mcp-content-empty '{"content":[]}')
P_MCP_EMPTY_TEXT=$(resp mcp-content-empty-text '{"content":[{"type":"text","text":"   "}]}')
P_MCP_ZERO=$(resp mcp-content-zero '{"content":[{"type":"text","text":"0"}]}')

# --- biting: one named case per cause of the original muteness ----------------
# A bare parts array is NOT "a non-empty array, therefore an answer".
P_REG_BARE=$(resp regression-bare-array-not-a-list '[{"type":"text","text":"null"}]')
# A `### …` header in front of the value must not defeat the anchored rungs.
P_REG_HEADER=$(resp regression-header-prefix '{"content":[{"type":"text","text":"### Result\n0"}]}')
# Neither must the section the server appends AFTER the value.
P_REG_TRAILING=$(resp regression-trailing-section "$(jq_env "$(report '[]')")")
P_HEADER_EMPTY=$(resp header-empty-after-strip '"### Result\n"')

# --- biting: the counter rung, the two shapes it used to miss -----------------
P_H1_LABELLED=$(resp h1-zero-labelled '{"matched":0,"total":0,"selector":".promo"}')
P_H1_NESTED=$(resp h1-zero-nested '{"result":{"matched":0,"total":0}}')

# --- biting: the third tool is really in scope --------------------------------
P_UNSAFE=$(mk run-code-unsafe-in-scope "$TOOL_UNSAFE" "$UNSAFE_INPUT" 'null')

# --- biting: the broken-idiom rung --------------------------------------------
# The response is a decided boolean everywhere here: the subject is the SOURCE.
P_IDIOM_ONLY=$(mk idiom-only-nonnull "$TOOL" "$IDIOM_FN" 'true')
P_IDIOM_NULL=$(mk idiom-and-null "$TOOL" "$IDIOM_FN" '0')
P_IDIOM_CHROME=$(mk idiom-chrome-text "$TOOL_CHROME" "$IDIOM_CHROME_INPUT" 'true')
P_IDIOM_BRACKET=$(mk idiom-bracket-access "$TOOL" "$IDIOM_BRACKET" 'true')
# The source cap must be the same on the named-field branch and the fallback.
PAD="$(head -c 25000 /dev/zero | tr '\0' 'x')"
BIG_FN="$("$JQ" -n --arg p "$PAD" '{function: ("() => { const pad = \"" + $p + "\"; return [...document.querySelectorAll(\"a\")].filter(e => e.offsetParent).length; }")}')"
BIG_UNKNOWN="$("$JQ" -n --arg p "$PAD" '{payloadBlob: ("() => { const pad = \"" + $p + "\"; return [...document.querySelectorAll(\"a\")].filter(e => e.offsetParent).length; }")}')"
P_IDIOM_BIG_FIELD=$(mk idiom-beyond-20000-known-field "$TOOL" "$BIG_FN" 'true')
P_IDIOM_BIG_FALLBACK=$(mk idiom-beyond-20000-fallback "$TOOL" "$BIG_UNKNOWN" 'true')

# --- mute: answers that are decided -------------------------------------------
P_NONZERO=$(resp nonzero-number '42')
P_NONEMPTY_STRING=$(resp nonempty-string '"found 3 links"')
P_NONEMPTY_ARRAY=$(resp nonempty-array '[1]')
P_OBJ_KEYS=$(resp object-with-keys '{"matched":3}')
P_MIXED_ZERO=$(resp mixed-zero-record '{"matched":0,"total":120}')
# A boolean is a decided answer, not an absence. `false` must never bite.
P_FALSE=$(resp boolean-false 'false')
P_TRUE=$(resp boolean-true 'true')
P_MCP_TEXT=$(resp mcp-content-text '{"content":[{"type":"text","text":"3 matches"}]}')
# REPLAYED polarity partners: the same wrapper, a value that is an answer.
P_REAL_LIST=$(resp real-bare-array-list "$(jq_bare "$(report '[1,2,3]')")")
P_REAL_42=$(resp real-bare-array-42 "$(jq_bare "$(report '42')")")
P_REAL_OK=$(resp real-bare-array-ok "$(jq_bare "$(report '"ok"')")")
P_REAL_FALSE=$(resp real-bare-array-false "$(jq_bare "$(report '{
  "ligneTrouvee": false
}')")")
P_REAL_SCROLLTOP=$(resp real-bare-array-scrolltop "$(jq_bare "$(report '{
  "active": "hdr2",
  "scrollTop": 0
}')")")
P_ARRAY_OBJECTS=$(resp array-of-plain-objects '[{"href":"/a"}]')
P_HEADER_NO_NL=$(resp header-only-no-newline '"### Result"')
P_HEADER_MID=$(resp header-mid-string '"3 matches\n### Result\n0"')
# Out of scope: the hook must exit before classifying anything.
P_WRONG_TOOL=$(mk wrong-tool "Bash" '{"command":"ls"}' 'null')
# FAIL-CLOSED: no tool_name at all is not an invitation to classify.
P_NO_TOOL_NAME=$(pay tool-name-absent \
  "{\"hook_event_name\":\"PostToolUse\",\"tool_input\":$BENIGN_INPUT,\"tool_response\":null}")
P_LOOKALIKE=$(mk idiom-lookalike "$TOOL" "$LOOKALIKE_INPUT" 'true')

# --- mute: a zero that is a MEASUREMENT, not an absence -----------------------
P_H1_COORDS=$(resp h1-origin-coords '{"x":0,"y":0}')
P_H1_CONSOLE=$(resp h1-clean-console '{"errors":0,"warnings":0}')
P_H1_SCROLL=$(resp h1-scroll-top '{"scrollY":0}')
P_H1_NEGZERO=$(resp h1-negzero '{"delta":-0}')

# --- mute: a decided STATE that reads like an absence -------------------------
# getComputedStyle(el).display === "none" is the commonest browser measurement
# there is, and a 404 page title is the answer to the question asked.
P_H2_NONE=$(resp h2-str-none '"None"')
P_H2_NOTFOUND=$(resp h2-str-notfound '"Not Found"')
P_H2_DISPLAY=$(resp h2-real-computed-display "$(jq_bare "$(report '"none"')")")

# --- mute: the idiom named where it is not used -------------------------------
P_IDIOM_COMMENT=$(mk idiom-in-avoidance-comment "$TOOL" "$IDIOM_COMMENT_INPUT" 'true')
P_IDIOM_STRLIT=$(mk idiom-in-string-literal "$TOOL" "$IDIOM_STRLIT_INPUT" 'true')
P_IDIOM_SELECTOR=$(mk idiom-in-selector-string "$TOOL" "$IDIOM_SELECTOR_INPUT" 'true')
P_IDIOM_CONCAT=$(mk idiom-concatenated-known-miss "$TOOL" "$IDIOM_CONCAT_INPUT" 'true')

# --- mute: an ERROR is not an absence -----------------------------------------
P_H3_ISERROR=$(resp h3-mcp-iserror '{"content":[{"type":"text","text":"null"}],"isError":true}')

# --- mute: UNREADABLE ---------------------------------------------------------
P_MALFORMED=$(pay malformed-json "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"$TOOL\",\"tool_response\":")
P_EMPTY_STDIN=$(pay empty-stdin '')
P_FIELD_ABSENT=$(pay field-absent \
  "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"$TOOL\",\"tool_input\":$BENIGN_INPUT}")
P_MCP_NONTEXT=$(resp mcp-content-nontext '{"content":[{"type":"image","data":"iVBORw0KGgo=","mimeType":"image/png"}]}')
P_BARE_NONTEXT=$(resp bare-array-nontext '[{"type":"image","data":"iVBORw0KGgo=","mimeType":"image/png"}]')
# Verbatim from the corpus: both recorded failures arrive in this shape.
P_REAL_ERROR=$(resp real-error-string '"Error: ### Error\nExecution context was destroyed, most likely because of a navigation.\n### Page\n- Page URL: http://localhost:5173/journalist/cars\n### Events\n- New console entries: .playwright-mcp/console.log#L49-L93"')

# ==============================================================================
# RUNNER
# ==============================================================================

PASS=0
FAIL=0
CASE_STATUS=0
NCASES=0

fail_case() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %-32s %s\n' "$1" "$2"
}
ok_case() {
  PASS=$((PASS + 1))
  printf 'ok    %-32s %s\n' "$1" "$2"
}

OUT_F=""
ERR_F=""

run_case() { # run_case <label> <payload>
  OUT_F="$WORK/out/$1.stdout"
  ERR_F="$WORK/out/$1.stderr"
  : > "$OUT_F"
  : > "$ERR_F"
  set +e
  "$NODE" "$SUT" < "$2" > "$OUT_F" 2> "$ERR_F"
  CASE_STATUS=$?
  set -e
}

echo "=== null-result-gate probe ==="
echo "    hook under test: $SUT"
echo

# label @ kind @ payload @ extra-jq-filter-over-stdout
# kind: bite = exactly one JSON object carrying a non-empty additionalContext
#       mute = stdout empty, byte for byte
while IFS='@' read -r label kind payload filt; do
  case "$label" in '' | '#'*) continue ;; esac
  NCASES=$((NCASES + 1))

  run_case "$label" "$payload"

  why=""
  # FORM, every case: the host must never see a non-zero exit, not even on
  # input the hook cannot parse.
  if [ "$CASE_STATUS" != "0" ]; then
    why="exit: expected 0, got $CASE_STATUS (stderr: $(head -c 200 "$ERR_F"))"
  fi
  # FORM, every case: stderr silent. A hook that logs to stderr on a degraded
  # path pollutes the session transcript for no benefit.
  if [ -z "$why" ] && [ -s "$ERR_F" ]; then
    why="stderr: expected empty, got $(head -c 200 "$ERR_F")"
  fi

  if [ -z "$why" ]; then
    case "$kind" in
      mute)
        if [ -s "$OUT_F" ]; then
          why="stdout: expected empty, got $(head -c 200 "$OUT_F")"
        fi
        ;;
      bite)
        if [ ! -s "$OUT_F" ]; then
          why="stdout: expected one JSON object, got nothing"
        elif ! "$JQ" -e -s 'length == 1 and (.[0] | type) == "object"' "$OUT_F" > /dev/null 2>&1; then
          why="stdout is not exactly one JSON object: $(head -c 200 "$OUT_F")"
        elif ! "$JQ" -e '.hookSpecificOutput.hookEventName == "PostToolUse"' "$OUT_F" > /dev/null 2>&1; then
          why="stdout json: hookSpecificOutput.hookEventName is not \"PostToolUse\": $(head -c 200 "$OUT_F")"
        elif ! "$JQ" -e '(.hookSpecificOutput.additionalContext | type) == "string" and (.hookSpecificOutput.additionalContext | length) > 0' "$OUT_F" > /dev/null 2>&1; then
          why="stdout json: additionalContext is missing or empty: $(head -c 200 "$OUT_F")"
        fi
        ;;
      *)
        why="unknown kind column: $kind"
        ;;
    esac
  fi

  if [ -z "$why" ] && [ -n "${filt:-}" ] && [ "$filt" != "-" ]; then
    if ! "$JQ" -e "$filt" "$OUT_F" > /dev/null 2>&1; then
      why="stdout json: [$filt] is false; got $(head -c 300 "$OUT_F")"
    fi
  fi

  if [ -n "$why" ]; then
    fail_case "$label" "$why"
  else
    ok_case "$label" "exit 0, $kind"
  fi
done << TABLE
# --- MUST BITE: the nullity rungs, plain values -------------------------------
null-literal@bite@$P_NULL_LITERAL@-
empty-string@bite@$P_EMPTY_STRING@-
whitespace-string@bite@$P_WS_STRING@-
zero-number@bite@$P_ZERO_NUMBER@-
zero-string@bite@$P_ZERO_STRING@-
empty-array@bite@$P_EMPTY_ARRAY@-
empty-object@bite@$P_EMPTY_OBJECT@-
no-matches-phrase@bite@$P_NO_MATCHES@-
all-zero-record@bite@$P_ALL_ZERO@-
# --- MUST BITE: the shapes that actually arrive (replayed) --------------------
real-bare-array-empty@bite@$P_REAL_EMPTY@-
real-bare-array-null@bite@$P_REAL_NULL@-
real-bare-array-zero@bite@$P_REAL_ZERO@-
real-bare-array-emptystr@bite@$P_REAL_EMPTYSTR@-
real-bare-array-quoted-zero@bite@$P_REAL_QZERO@-
real-bare-array-counter-zero@bite@$P_REAL_COUNTER@-
real-bare-string-zero@bite@$P_REAL_STR_ZERO@-
# --- MUST BITE: the documented envelope, never observed but kept --------------
mcp-content-empty@bite@$P_MCP_EMPTY@-
mcp-content-empty-text@bite@$P_MCP_EMPTY_TEXT@-
mcp-content-zero@bite@$P_MCP_ZERO@-
# --- MUST BITE: one named case per cause of the original muteness -------------
regression-bare-array-not-a-list@bite@$P_REG_BARE@-
regression-header-prefix@bite@$P_REG_HEADER@-
regression-trailing-section@bite@$P_REG_TRAILING@-
header-empty-after-strip@bite@$P_HEADER_EMPTY@-
# --- MUST BITE: the counter rung, the two shapes it used to miss --------------
h1-zero-labelled@bite@$P_H1_LABELLED@-
h1-zero-nested@bite@$P_H1_NESTED@-
# --- MUST BITE: the third tool is really in scope -----------------------------
run-code-unsafe-in-scope@bite@$P_UNSAFE@-
# --- MUST BITE: the broken-idiom rung, and the two rungs kept separate --------
idiom-only-nonnull@bite@$P_IDIOM_ONLY@.hookSpecificOutput.additionalContext as \$c | (\$c | test("checkVisibility")) and (\$c | test("dénominateur") | not)
idiom-and-null@bite@$P_IDIOM_NULL@.hookSpecificOutput.additionalContext as \$c | (\$c | test("checkVisibility")) and (\$c | test("dénominateur"))
idiom-chrome-text@bite@$P_IDIOM_CHROME@.hookSpecificOutput.additionalContext | test("checkVisibility")
idiom-bracket-access@bite@$P_IDIOM_BRACKET@.hookSpecificOutput.additionalContext | test("checkVisibility")
idiom-beyond-20000-known-field@bite@$P_IDIOM_BIG_FIELD@.hookSpecificOutput.additionalContext | test("checkVisibility")
idiom-beyond-20000-fallback@bite@$P_IDIOM_BIG_FALLBACK@.hookSpecificOutput.additionalContext | test("checkVisibility")
# --- MUST STAY MUTE: decided answers ------------------------------------------
nonzero-number@mute@$P_NONZERO@-
nonempty-string@mute@$P_NONEMPTY_STRING@-
nonempty-array@mute@$P_NONEMPTY_ARRAY@-
object-with-keys@mute@$P_OBJ_KEYS@-
mixed-zero-record@mute@$P_MIXED_ZERO@-
boolean-false@mute@$P_FALSE@-
boolean-true@mute@$P_TRUE@-
mcp-content-text@mute@$P_MCP_TEXT@-
real-bare-array-list@mute@$P_REAL_LIST@-
real-bare-array-42@mute@$P_REAL_42@-
real-bare-array-ok@mute@$P_REAL_OK@-
real-bare-array-false@mute@$P_REAL_FALSE@-
real-bare-array-scrolltop@mute@$P_REAL_SCROLLTOP@-
array-of-plain-objects@mute@$P_ARRAY_OBJECTS@-
header-only-no-newline@mute@$P_HEADER_NO_NL@-
header-mid-string@mute@$P_HEADER_MID@-
wrong-tool@mute@$P_WRONG_TOOL@-
tool-name-absent@mute@$P_NO_TOOL_NAME@-
idiom-lookalike@mute@$P_LOOKALIKE@-
# --- MUST STAY MUTE: a zero that is a MEASUREMENT -----------------------------
h1-origin-coords@mute@$P_H1_COORDS@-
h1-clean-console@mute@$P_H1_CONSOLE@-
h1-scroll-top@mute@$P_H1_SCROLL@-
h1-negzero@mute@$P_H1_NEGZERO@-
# --- MUST STAY MUTE: a decided STATE that reads like an absence ---------------
h2-str-none@mute@$P_H2_NONE@-
h2-str-notfound@mute@$P_H2_NOTFOUND@-
h2-real-computed-display@mute@$P_H2_DISPLAY@-
# --- MUST STAY MUTE: the idiom named where it is not used ---------------------
idiom-in-avoidance-comment@mute@$P_IDIOM_COMMENT@-
idiom-in-string-literal@mute@$P_IDIOM_STRLIT@-
idiom-in-selector-string@mute@$P_IDIOM_SELECTOR@-
idiom-concatenated-known-miss@mute@$P_IDIOM_CONCAT@-
# --- MUST STAY MUTE: an ERROR is not an absence -------------------------------
h3-mcp-iserror@mute@$P_H3_ISERROR@-
# --- MUST STAY MUTE: UNREADABLE, asserted on emptiness alone ------------------
malformed-json@mute@$P_MALFORMED@-
empty-stdin@mute@$P_EMPTY_STDIN@-
field-absent@mute@$P_FIELD_ABSENT@-
mcp-content-nontext@mute@$P_MCP_NONTEXT@-
bare-array-nontext@mute@$P_BARE_NONTEXT@-
real-error-string@mute@$P_REAL_ERROR@-
TABLE

# Derived, never declared: the mutant driver reads this back instead of
# carrying a constant that rots the first time a case is added.
echo "runtime-cases: $NCASES"

# ==============================================================================
# WIRING — the inertia detector
# ==============================================================================

# wired-inherit: the hook is pulled out of hooks.nix by name.
if grep -qE '^[[:space:]]*hookNullResultGate[[:space:]]*$' "$CLAUDE_NIX"; then
  ok_case wired-inherit "hookNullResultGate inherited in home/claude-code.nix"
else
  fail_case wired-inherit "hookNullResultGate is not inherited in home/claude-code.nix"
fi

# wired-file: it is materialised on disk as a real file.
if grep -qE 'hooks/null-result-gate\.js"[[:space:]]*=[[:space:]]*\{' "$CLAUDE_NIX" \
  && grep -qE 'text[[:space:]]*=[[:space:]]*hookNullResultGate;' "$CLAUDE_NIX"; then
  ok_case wired-file "hooks/null-result-gate.js written from hookNullResultGate"
else
  fail_case wired-file "hooks/null-result-gate.js is not materialised from hookNullResultGate"
fi

# The PostToolUse block of settings.nix, by line range. Grepping the whole file
# would score the hook as registered no matter which event it was attached to.
PTU_START="$(grep -nE '^[[:space:]]{6}PostToolUse = \[' "$SETTINGS_NIX" | head -1 | cut -d: -f1 || true)"
PTU_END=""
if [ -n "$PTU_START" ]; then
  PTU_END="$(awk -v s="$PTU_START" 'NR>s && /^ {6}\];[[:space:]]*$/ {print NR; exit}' "$SETTINGS_NIX")"
fi
NRG_LINE="$(grep -nE 'null-result-gate\.js' "$SETTINGS_NIX" | head -1 | cut -d: -f1 || true)"

if [ -n "$PTU_START" ] && [ -n "$PTU_END" ] && [ -n "$NRG_LINE" ] \
  && [ "$NRG_LINE" -gt "$PTU_START" ] && [ "$NRG_LINE" -lt "$PTU_END" ]; then
  ok_case wired-settings "null-result-gate.js registered inside PostToolUse (line $NRG_LINE)"
else
  fail_case wired-settings "null-result-gate.js is not inside the PostToolUse block (start=${PTU_START:-?} end=${PTU_END:-?} line=${NRG_LINE:-?})"
fi

# matcher-agrees: the settings matcher and the hook's TOOLS constant must be
# the SAME SET, checked in both directions.
SETTINGS_MATCHER=""
if [ -n "$NRG_LINE" ]; then
  SETTINGS_MATCHER="$(awk -v e="$NRG_LINE" '
    NR < e && /^[[:space:]]*matcher = "/ {
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/".*$/, "", line)
      last = line
    }
    NR == e { print last; exit }
  ' "$SETTINGS_NIX")"
fi
HOOK_TOOLS="$(sed -n 's/.*const TOOLS = \[\(.*\)\].*/\1/p' "$SUT" | head -1 | tr -d '" ' | tr ',' '\n' | grep -v '^$' | sort || true)"
MATCHER_TOOLS="$(printf '%s\n' "$SETTINGS_MATCHER" | tr '|' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort || true)"
# A matcher made only of [A-Za-z0-9_-], space, `,` and `|` is a list of EXACT
# strings, not a regex. Adding `.*` would flip it to regex mode for no gain.
REFERENCE="mcp__claude-in-chrome__javascript_tool|mcp__playwright__browser_evaluate|mcp__playwright__browser_run_code_unsafe"
REF_TOOLS="$(printf '%s\n' "$REFERENCE" | tr '|' '\n' | sort)"

ONLY_IN_MATCHER="$(comm -23 <(printf '%s\n' "$MATCHER_TOOLS") <(printf '%s\n' "$HOOK_TOOLS") | tr '\n' ' ')"
ONLY_IN_HOOK="$(comm -13 <(printf '%s\n' "$MATCHER_TOOLS") <(printf '%s\n' "$HOOK_TOOLS") | tr '\n' ' ')"
if [ -z "$MATCHER_TOOLS" ] || [ -z "$HOOK_TOOLS" ]; then
  fail_case matcher-agrees "could not read both sides (matcher='$SETTINGS_MATCHER', TOOLS='$(printf '%s' "$HOOK_TOOLS" | tr '\n' ',')')"
elif [ -n "$ONLY_IN_MATCHER" ] || [ -n "$ONLY_IN_HOOK" ]; then
  fail_case matcher-agrees "sets differ — only in matcher: [${ONLY_IN_MATCHER% }] ; only in hook TOOLS: [${ONLY_IN_HOOK% }]"
elif [ "$MATCHER_TOOLS" != "$REF_TOOLS" ]; then
  fail_case matcher-agrees "both sides agree but drifted from the reference string: $REFERENCE"
else
  ok_case matcher-agrees "both directions, and equal to the reference string"
fi

# not-async: async = true would defer additionalContext to the NEXT turn, by
# which time the probe is no longer the subject.
if [ -n "$NRG_LINE" ]; then
  BLOCK_START="$(awk -v e="$NRG_LINE" 'NR < e && /^ {12}\{[[:space:]]*$/ { last = NR } NR == e { print last; exit }' "$SETTINGS_NIX")"
  BLOCK_END="$(awk -v s="$NRG_LINE" 'NR >= s && /^ {12}\}[[:space:]]*$/ { print NR; exit }' "$SETTINGS_NIX")"
else
  BLOCK_START=""
  BLOCK_END=""
fi
if [ -z "$BLOCK_START" ] || [ -z "$BLOCK_END" ]; then
  fail_case not-async "could not delimit the registered hook block (start=${BLOCK_START:-?} end=${BLOCK_END:-?})"
elif sed -n "${BLOCK_START},${BLOCK_END}p" "$SETTINGS_NIX" | grep -qE '^[[:space:]]*async[[:space:]]*='; then
  fail_case not-async "the registered block carries async — additionalContext would arrive a turn late"
else
  ok_case not-async "the registered block carries no async (lines $BLOCK_START-$BLOCK_END)"
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
