#!/usr/bin/env node
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    const ti = data.tool_input || {};
    if (ti.skill !== "apex") process.exit(0);

    const args = typeof ti.args === "string" ? ti.args : "";
    // `nix`, `flake` and `rebuild` were in STANDARD and had to go: in a
    // nix-darwin config repo every task names a .nix file, so they matched
    // everything and made the trivial tier unreachable (that tier was itself
    // removed on 2026-08-17). Measured against the real briefs of
    // 2026-08-08 — a two-line CLAUDE.md edit escalated to -b -s -t -pr
    // purely because the path contained "claude-md.nix".
    // A signal that fires on every task is not a signal.
    const HIGH = /(hook|settings|permission|sandbox|deny|secret|credential)/i;
    const STANDARD = /(supprime|delete|remove|\brm\b|migration|\bmaster\b|\bmain\b|\bprod\b)/i;

    let target;
    // Leading tokens that look like flags; everything after is the task.
    const parts = args.trim().split(/\s+/);
    let i = 0;
    while (i < parts.length && /^-[a-zA-Z0-9]+$/.test(parts[i])) i++;
    const typed = parts.slice(0, i);
    const rest = parts.slice(i).join(" ");

    // -e now means external verify: one cross-vendor read-only pass over
    // the same diff. The hook must never STRIP it — deleting a typed flag
    // makes the feature inert with no error anywhere. It is ADDED only on a
    // HIGH signal, mirroring the High-stakes default set of the Mode Gate;
    // a typed -E still wins (the uppercase-OFF loop below). STANDARD never
    // adds it: another vendor's round-trip is spent only where a miss is
    // expensive.
    const kept = typed.slice();

    // Branch and save left the flag surface: both are mode invariants now,
    // so the tiers only carry what is still a real flag.
    const isHigh = HIGH.test(args);
    if (isHigh) target = ["-t", "-x", "-pr", "-e"];
    else if (STANDARD.test(args)) target = ["-t", "-pr"];
    else process.exit(0);

    // Add what is missing, but never override an explicit uppercase OFF.
    for (const f of (target || [])) {
      const off = "-" + f.slice(1).toUpperCase();
      if (kept.indexOf(f) === -1 && kept.indexOf(off) === -1) kept.push(f);
    }

    const next = (kept.join(" ") + " " + rest).trim();

    // The Fable spend is decided here, by regex, not by the coordinator's
    // judgement mid-run — that judgement is exactly what kept getting
    // skipped. HIGH only: not because the quota is scarce (measured here,
    // 21 Fable spawns against 6489 coordinator messages — it never bound),
    // but because an independent read is worth its round-trip only where a
    // miss is expensive, which is what ORCHESTRATION.md keeps it for.
    const fable = isHigh
      ? "HIGH risk signal in this brief (hook/settings/permission/sandbox/deny/secret/"
        + "credential). The Fable read-only pass is MANDATORY for this run: once the "
        + "machine gate is green, spawn a subagent with an explicit model: fable over "
        + "the REAL diff plus the ACs, then apply its bounded fix-list. Fable is "
        + "read-only — it returns PASS or a fix-list and never edits. Unless -E was "
        + "typed, the external cross-vendor pass (-e) also runs, IN ADDITION TO the "
        + "Fable pass, never instead of it; a BLOCKED external verdict is an unrun check. "
        + "Fast mode is NOT eligible for this run."
      : null;

    // Emit even when the flags are already right: without this the context
    // is dropped whenever the user typed -t -x -pr themselves.
    const unchanged = next === args.trim();
    if (unchanged && !fable) process.exit(0);

    // When there is nothing to rewrite, send the context ALONE. Adding
    // permissionDecision "allow" here would auto-approve the Skill call and
    // bypass every downstream check, to rewrite nothing.
    if (unchanged) {
      // Only the nested form carrying hookEventName is documented.
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: fable }
      }));
      process.exit(0);
    }

    const out = {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: { skill: ti.skill, args: next }
      }
    };
    // Nested, like its twin twelve lines up. A root-level
    // `additionalContext` is not read by any event: on THIS branch — the
    // frequented one, taken by every bare `/apex` whose flags get
    // rewritten — the Fable instruction reached nobody.
    if (fable) out.hookSpecificOutput.additionalContext = fable;
    process.stdout.write(JSON.stringify(out));
  } catch (e) {}
  process.exit(0);
});
