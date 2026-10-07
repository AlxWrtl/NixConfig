# Hook scripts for Claude Code
# All command hooks: read JSON from stdin, exit 0 + JSON stdout
# permissionDecision: "allow" | "deny" | "ask"
# Bodies live in ./hooks/<deployed name>, read verbatim. The 4 bodies that
# need a nix value carry a placeholder; `subst` throws if it is missing, so a
# renamed placeholder cannot ship a hook with the literal still in it.
{
  graphifyReindexPkg,
  vaultSnapshotPkg,
  alxVaultPath,
}:
let
  subst =
    file: from: to:
    let
      t = builtins.readFile file;
      r = builtins.replaceStrings [ from ] [ to ] t;
    in
    if r == t then throw "hooks.nix: placeholder ${from} not found in ${toString file}" else r;
in
{
  hookProtectMain = subst ./hooks/protect-main.js (builtins.toJSON "@alxVaultPath@") (
    builtins.toJSON alxVaultPath
  );

  # PreToolUse on Agent and SendMessage: a hard cap on APEX correction rounds
  # (run 62). A correction round goes through either channel, a fresh spawn
  # or a re-brief sent to a live agent, and both are counted. Its brief
  # carries `APEX-CORRECTION-ROUND: <run-id>`; each round claims the first
  # free slot ~/.claude/apex-correction-budget/<run-id>.round<n>, n in
  # 1..MAX_ROUNDS (outside the Bash sandbox's writable paths), and the round
  # finding none is denied. A slot is created exclusively (O_EXCL), so
  # parallel marked spawns cannot both take the last one. A round counts
  # when the spawn/send is attempted (PreToolUse), even if a later hook or
  # the user then denies it. A brief naming 06-resolve.md or a correction
  # round must carry the marker, with a run-id or `none`. Unmarked,
  # unrelated or unreadable input is let through: it cannot be told apart
  # from normal Agent use. Once a marker names a run, every failure denies:
  # fail-open is the unbounded loop this hook exists to stop. Guardrail, not
  # barrier: `none` is a visible claim.
  hookCorrectionBudget = builtins.readFile ./hooks/correction-budget.js;

  # Turns the APEX routing rule from advice into enforcement. The
  # UserPromptSubmit reminder is text: it is read and then skipped. Measured on
  # 2026-08-08 — 6 file-modifying tasks in one session, APEX invoked on 2.
  #
  # Fires ONCE PER TASK (2026-08-16). It used to fire once per SESSION: the
  # check was a substring scan of the whole transcript, so the first APEX run
  # cleared every later edit — a second request in the same conversation went
  # through with no workflow at all. The scan now walks BACKWARDS from the end
  # and stops at the last real user turn, so only an APEX invoked since that
  # turn counts.
  #
  # "Real user turn" excludes tool_result blocks (138 of the 164 user-typed
  # lines in a measured 937-line transcript) and `! command` lines, which are
  # user input but not a new request.
  #
  # Cost of the change: one deny -> apex -> retry round trip per modifying
  # task, instead of one per session. That is the point.
  #
  # INTERPRETER WRITES (2026-09-25). The Bash door read shell syntax only, so a
  # python/node/ruby script edited the repo unseen. What shipped, as replayed
  # with this hook's own source over the recorded Bash calls: 0 earlier denies
  # lost, in both replays. New denies: +29 over 20 645 rows with the scripts as
  # they are on disk today — most out-of-repo scripts have since been deleted,
  # so the script rule's bulk cannot be re-run that way; +66 over 20 072 unique
  # (cmd, cwd) pairs with deleted scripts served from their recovered text, 42
  # of them script runs, 0 on read-only or module calls (`-m`). The split of
  # those 66 into real edits and false positives has NOT been audited row by
  # row; a false positive costs one stray apex call. `perl -0pi` counts as
  # in-place (21 unique passes before).
  # CORRECTION: +29, +66 and 42 were measured on a DRAFT of this hook, which
  # read git's answer with `.toString().trim()`. The shipped hook reads it with
  # `{ encoding }` + `.trim()`; that harness's fake execSync returned a Buffer
  # whatever the options, so on the shipped hook `.trim()` threw into the
  # silent catch and every script-rule deny was skipped. Those three figures
  # are void for what shipped. Re-measured with the fixed harness (replay2),
  # shipped hook against its predecessor, same 20 072 unique (cmd, cwd):
  # 1966 earlier denies, 0 lost, +66 new (42 script runs, 5 inline writes, 19
  # `perl -0pi` rows the classifier calls inline reads). +29 was not
  # re-measured. The shipped hook's own baseline is 2032 denies.
  #
  # HARDENING (2026-09-25, second pass).
  #   (a) Shell-door timing. Four quadratic regexes (noTemp twice, AT_CMD,
  #       WRITES[0]) took 6.8 s on 64 KB shapes and over 30 s on
  #       `/.claude/projects/` repeated: past the 5 s timeout, so fail-open.
  #       Now under 200 ms on the probe's fast-* shapes. A command over 256 K
  #       chars is denied without being read (the longest unique recorded
  #       call is 44 497 chars).
  #   (b) Script rule: env fallback for a name the command never sets, `cd`
  #       tracking, separate-argument flags (SEP_ARG: -r -W -X -I, --import,
  #       --require, --loader, --experimental-loader, --env-file), quoted
  #       head + bare tail (`"$TMPDIR"/edit.py`).
  #   (c) `codex exec`: denied without APEX when the session cwd, `-C <dir>`
  #       or the dir the `cd`s lead to is a repo, unless an explicit,
  #       unwidened `-s read-only`. One exemption, a whitelist that fails
  #       closed: every `cd` before the call top level and resolved, landing
  #       in an existing non-repo dir under a temp root, with no `-C` and no
  #       danger flag (danger sandbox, bypass, `--yolo`, `--add-dir`, `-p`, a
  #       `-c` key naming sandbox/approval/permission/profile).
  #   Replay against the pre-PR hook, 20 072 unique (cmd, cwd): 0 lost; new
  #   denies 6 = cd 4 (1 true, 3 false positives from the script rule's
  #   "names the repo, writes anywhere" test; split read by audit.js and
  #   audit2.js over the recovered scripts, recovered.json, in the hardening
  #   session's scratchpad) + codex 2: `-C <portfolio>`
  #   (true) and `cd <scratch> && codex exec … -C "$(pwd)"` (false positive:
  #   codex runs in the scratch dir, but any `-C` voids the exemption).
  #
  # What still goes through, named so it is not mistaken for coverage.
  # IRREDUCIBLE (no static reading decides it):
  #   - a variable unset in the hook's environment and not assigned earlier in
  #     the same command: loop var, `read`, `$1`, sourced or shell-snapshot
  #     names, `$(...)`;
  #   - a path built at run time;
  #   - a write done by a CHILD: subprocess, os.system, exec of another tool.
  #   - CDPATH: a relative `cd x` resolves through the SHELL's CDPATH, which
  #     is not the hook's; the codex walk resolves it from the cwd.
  # UNCODED (could be read, is not):
  #   - script rule: `(cd x); python3 y.py` is read as if the `cd` moved the
  #     shell (errs toward a false positive); for codex a `cd` inside `(...)`
  #     or `$(...)` voids the temp exemption instead;
  #   - `pushd`, `cd -`, `ruby -C` (script rule; codex fails closed on them);
  #   - `python3 <<< "code"` (a here-string) and `<<\EOF` (escaped delimiter);
  #   - `/usr/bin/env python3 -c`, `bun run` / `deno run` of a script,
  #     `uv run python -c`;
  #   - an interpreter after `then`, `do`, `{` or `!` — command position is
  #     read after separators and env/timeout/VAR= prefixes only;
  #   - more than 16 flags before `-c`;
  #   - a 5th script in one command: only 4 are read. Measured with
  #     R_SCRIPT_RAW, uncapped, over 20 034 unique recorded commands: 16 hold
  #     exactly 4 scripts and 10 hold 5 to 8, whose later scripts go unread;
  #   - the codex gate reads 4 exec calls and 64 `codex` words; the rest are
  #     graded at the session cwd, not read (most exec calls in one recorded
  #     command: 4, once);
  #   - a flag taking a separate argument outside the SEP_ARG set;
  #   - a script path made of 3+ quoted and bare pieces;
  #   - `codex apply`, `codex review`, `codex fork`, `codex "exec"` (a quoted
  #     subcommand is blank), `codex $'exec'` and `ex""ec` (a word glued
  #     from pieces is not read);
  #   - a `cd` the fold cannot see: quoted or escaped (`\cd`, `"cd"`,
  #     `c\d`) or run by `eval "cd ..."`; it moves the shell unseen, so the
  #     codex walk grades the dir before it;
  #   - codex after more than 16 `VAR=` / env prefixes;
  #   - codex after `npx`, `pnpm dlx @openai/codex`, `command`, `sudo`,
  #     `nice`, `xargs`, `env -u X`, `timeout -k N`, `then`, `do`, `{`, `!`
  #     or `bash -c`: command position
  #     is read past `env`/`nohup`/`time`/`exec`/`timeout N`/`VAR=` only;
  #   - `-c sandbox_mode=...` whose key is an unresolved `$VAR`;
  #   - `-s $VAR` is graded as not read-only (a false positive when it holds
  #     read-only) and voids the temp exemption;
  #   - `-o <file>` under `-s read-only`: codex writes its last message there;
  #   - writable roots added by codex's own config: the git-workspace profile
  #     adds the vault, whatever the command line says;
  #   - AT_CMD no longer sees `;\rcp` or `$(\fcp` (blanks are `[ \t]` now);
  #   - WRITES[0] misses an `-i` more than 1024 chars after `sed`/`perl`/`ruby`
  #     with no separator between.
  # And the other way: any `-C` voids the codex temp exemption, even
  # `-C "$(pwd)"` right after a `cd` into scratch; the write API is looked for
  # in the WHOLE command, so
  # `python3 -c "print(1)"; echo "open(f, 'w')"` counts the echoed text
  # against the interpreter.
  #
  # FAIL-OPEN on any error, unlike protect-main and block-main-bash. This is a
  # workflow hook, not a safety one: a missed APEX costs little, a session
  # where no edit can land costs a lot.
  hookRequireApex = builtins.readFile ./hooks/require-apex.js;

  # Turns the React Docs Gate from advice into a delivered reminder.
  #
  # rules/react.md carries the same content, but a path-scoped rule loads only
  # when a matching file is READ — an edit written from memory, with no prior
  # read, never triggers it. This hook closes that hole: it fires on the write
  # itself.
  #
  # Emits `additionalContext` ONLY, with no permissionDecision. Returning
  # "allow" here would bypass every downstream check — require-apex,
  # protect-main, block-main-bash — on any .tsx edit. Staying silent on the
  # decision keeps the normal permission flow intact.
  #
  # Once per session, keyed on session_id: a React session edits many files and
  # a per-edit reminder would be noise. FAIL-OPEN — a missed reminder costs a
  # doc lookup, never an edit.
  hookReactDocsGate = builtins.readFile ./hooks/react-docs-gate.js;

  # PostToolUse gate on the three browser-probe tools. A probe that returns
  # nothing is the most misread result there is: a zero gets reported as a
  # finding when the instrument was never shown to be able to return anything
  # at all. `matched: 0, total: 0` is the signature of that failure.
  #
  # Two INDEPENDENT triggers, because the worst case is the one where they
  # disagree: an `offsetParent` probe returns a non-zero count that is still
  # wrong (it undercounts `position: fixed`). B must be able to fire on a
  # non-null result.
  #
  # BUILT FROM REPLAYED TRAFFIC, not from the shapes that would be convenient
  # to read. The first version scored 33/33 on its own probe and was mute on
  # 190/190 real calls, because the fixtures were invented. Measured over 717
  # local transcripts:
  #   - `tool_response` is a BARE parts array `[{type:"text",text:"…"}]`
  #     (188/190) or a bare string (2/190). The documented `{content:[…]}`
  #     envelope: 0/190.
  #   - the text it carries is a markdown REPORT, not a value:
  #     `### Result\n<json>\n### Ran Playwright code\n…` (186/190).
  # Every rung below is anchored, so both of those made all of them fail.
  #
  # The symmetric failure is a gate that shouts, so each widening is paired
  # with a measured value it must NOT fire on: `{errors:0,warnings:0}` is a
  # CLEAN console, `{x:0,y:0}` is the origin, `getComputedStyle(el).display`
  # is `"none"`, a 404 page title is `"Not Found"`, and `isError:true` is a
  # crash. None of those is an absence. `checks/null-result-gate-probe.sh`
  # asserts both polarities and grades the mutants that prove it.
  #
  # Silence is the default and the only alternative to firing: no stdout, no
  # stderr, exit 0, in every path including a parse failure.
  hookNullResultGate = builtins.readFile ./hooks/null-result-gate.js;

  # Rewrites APEX's flags before it starts, from risk signals in the task text.
  #
  # The mode gate picks flags from prose, before anything is known about the
  # change — and a typed flag wins over the mode default. Measured on
  # 2026-08-08: `-e` was typed on 3 of 3 invocations, under-powering 2 of them
  # (a 45-rule rewrite and a blocking hook both ran in economy). That evidence
  # is what eventually retired economy mode entirely on 2026-08-17.
  #
  # Rule: a typed flag is a FLOOR, never a ceiling. A risk signal can only
  # raise the tier. `-e` (external verify) is never stripped when typed, and is
  # added only on a HIGH signal, as part of the High-stakes set — see below.
  # Uppercase disables the user typed on purpose are preserved.
  #
  # False positives are the intended failure direction: a task that merely
  # mentions "settings" runs more thoroughly than needed. Cheap. The reverse
  # is not.
  #
  # FAIL-OPEN: any error leaves the call untouched.
  hookApexFlags = builtins.readFile ./hooks/apex-flags.js;

  hookFormatTypescript = builtins.readFile ./hooks/format-typescript.js;

  hookBlockMainBash = subst ./hooks/block-main-bash.js (builtins.toJSON "@alxVaultPath@") (
    builtins.toJSON alxVaultPath
  );

  hookSessionStart = builtins.readFile ./hooks/session-start.sh;

  # SessionEnd: refresh the AlxVault knowledge graph. Reason for existing: the
  # APEX step-09b text instruction only fires when the model remembers it —
  # measured 2026-08-24, session notes written at 23:09, reindex never launched.
  # A hook fires whether or not the model thinks of it.
  # SessionEnd hooks share a 1.5 s budget, raised to the declared `timeout`
  # (60 s ceiling), so everything here must be a few milliseconds of shell and
  # the real work must leave. `async` detaches the hook from Claude Code's
  # lifecycle; `nohup` is what makes the GRANDCHILD (the reindex itself, minutes
  # long) survive the hook's own death, while the `( … & )` around it double-forks
  # out of the process group, which `nohup` alone does not cover — it only blocks
  # SIGHUP, and a group kill would still take the reindex with it. No matcher on
  # purpose: a malformed matcher silently never matches and the hook never runs —
  # the trap already measured in settings.nix (see the Stop/Bash `if` comment).
  # All five `reason` values mean the same thing here, so `reason` is logged as a
  # trace and never used as logic.
  # No jq, no `stat -c`: this file is deployed by home.file, NOT by
  # writeShellApplication, so it has none of the GNU runtimeInputs. A `stat -c`
  # would produce a rotation that never rotates — a silent failure.
  # Child output goes to this hook's own log deliberately: reindex.log stays
  # empty when the graph is already fresh, so without it nothing would prove the
  # hook ever fired.
  # The order below is the whole point, and each step earns its place. The
  # recursion guard reads only the environment, so it stays first and costs
  # nothing. The log directory is then created, and the log falls back to
  # /dev/null if it still cannot be opened: measured, a missing ~/GraphVault made
  # the `>>` redirection fail, and bash then skips the command entirely — the
  # reindex never left, and nothing recorded that it hadn't. Being unable to
  # trace must never be able to stop the work. Rotation copies and truncates in
  # place instead of renaming, because a `mv` unlinks the inode that the still
  # running `nohup` child holds open in O_APPEND, and every line it would emit —
  # including the `OK — N nodes` verdict that is the only evidence of a real run
  # — disappears with it; the temporary carries `.$$` so two sessions rotating at
  # once cannot clobber each other. The occupancy guard matches `graphify
  # extract` and never `graphify` alone, which would hit the always alive
  # graphify-mcp server and leave the hook permanently mute; if pgrep is missing
  # the hook proceeds rather than fail closed. Finally the work is launched
  # BEFORE stdin is read: everything used to sit downstream of `INPUT=$(cat)`, so
  # an unclosed stdin got the hook killed at the declared timeout and the
  # timeout mitigation turned into a silent no-fire. Reading stdin last means a
  # hanging stdin costs the trace line, not the trigger — and the child's own
  # output into this same log remains proof either way.
  hookGraphifyReindex =
    subst ./hooks/graphify-reindex.sh "@graphifyReindexPkg@"
      "${graphifyReindexPkg}";

  # UserPromptSubmit: stdout is injected into the turn's context. Kept to one
  # short line because this cost is paid on EVERY prompt. Unconditional by
  # design: keyword-matching the prompt would miss exactly the ambiguous cases
  # where the reminder matters most, and a false negative is the failure mode
  # that actually hurts (the rule silently not firing).
  # DUPLICATION: the mode table below is a hand-maintained COPY of the Mode
  # Gate table in skills.nix (apexStep00Init -> step-00-init.md), not derived
  # from it — still edited by hand. It drifted twice ((1) the trivial tier,
  # removed 2026-08-17, stayed advertised for months; (2) -o/-n became mode
  # defaults while still listed as opt-in), so drift is now guarded:
  # `modeDrift`, with `trivialAdvertised`, `missingOptions` and `staleOptions`,
  # in checks/apex-consistency.nix fails `nix flake check` when this line and
  # the table disagree.
  hookApexReminder = builtins.readFile ./hooks/apex-reminder.sh;

  hookSubagentStop = builtins.readFile ./hooks/subagent-stop.js;

  hookNotification = builtins.readFile ./hooks/notification.sh;

  hookCompactContext = builtins.readFile ./hooks/compact-context.sh;

  # Quality gate — scan recent changes for anti-patterns on Stop
  hookQualityGate = builtins.readFile ./hooks/quality-gate.js;

  # Governance audit log — append-only log of significant tool calls
  hookGovernanceAudit = builtins.readFile ./hooks/governance-audit.js;

  hookCircuitBreaker = builtins.readFile ./hooks/circuit-breaker.js;

  hookCircuitBreakerReset = builtins.readFile ./hooks/circuit-breaker-reset.js;

  hookStopFailure = builtins.readFile ./hooks/stop-failure.sh;

  # Encrypted off-machine snapshot at session end. Detached with nohup for the
  # same reason as the reindex: the work must outlive Claude Code's exit, and
  # `timeout` here only bounds the stdin read. Never blocks the session — a
  # failed backup is logged, not surfaced as a hook error.
  #
  # It is the vault's ONLY off-machine copy: ~/Vaults is outside iCloud and no
  # Time Machine destination is configured on this machine.
  hookVaultSnapshot = subst ./hooks/vault-snapshot.sh "@vaultSnapshotPkg@" "${vaultSnapshotPkg}";
}
