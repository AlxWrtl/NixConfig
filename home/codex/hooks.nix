# Codex hooks — the single source for ~/.codex/hooks.json AND for the trust
# keys handed to the verifier. One expression, two outputs, so the keys can
# never describe a file other than the one actually generated.
#
# ORDERING CONTRACT — READ THIS BEFORE ADDING A HOOK
#   Codex records trust per hook, POSITIONALLY, as
#     [hooks.state."<abs hooks.json>:<snake_event>:<group index>:<hook index>"]
#   The index is the identity. Therefore:
#     * APPEND ONLY, and only at the END of an event's list. Inserting a hook
#       at position k invalidates the trust of every group at or after k, and
#       an un-trusted hook is SKIPPED IN SILENCE — no error, no log, no
#       protection, while the configuration still looks correct.
#     * Editing an existing hook's command or timeout changes its content
#       hash, which un-trusts it just the same. Re-approve it with the /hooks
#       command inside a Codex session.
#   `hookList` below is a LIST for exactly that reason and must never become
#   an attribute set: nix sorts attribute names alphabetically and would
#   reorder the file — and with it the trust keys — behind your back.
#
# TIMEOUTS ARE PART OF THE SECURITY ARGUMENT, NOT A TUNING KNOB
#   Codex treats every non-zero exit other than 2 as "did not block", so a
#   hook the host kills GRANTS what it exists to refuse. Each script therefore
#   refuses itself first, on its own watchdog: protect-main at 3000 ms,
#   block-main-shell at 3000 ms, quality-gate at 4000 ms. The registered
#   timeout must stay above all three — 5, NEVER below 4. Lower it and the host
#   kills the hook before its watchdog fires, and the fail-closed property is
#   gone with no visible symptom.
#   Change it here and you must change the constant in the script too.
#
# INTERPRETER — the absolute system node, deliberately NOT
#   ${pkgs.nodejs_22}/bin/node. A pinned store path moves on every nixpkgs
#   bump; that would rewrite both command strings, change the hooks file's
#   content hash, and silently un-trust the security hook on an update that
#   has nothing to do with it. /run/current-system/sw/bin/node is also what
#   the live hooks.json already uses.
{ pkgs }:

let
  nodeBin = "/run/current-system/sw/bin/node";

  # Real .js files, read in — never hook bodies written as nix strings, which
  # is where the escaping hazard lives and what stops the offline harness from
  # executing the very same bytes. Executable, and in the store: the store is
  # read-only, so the agent cannot rewrite its own guard, and that property
  # does not depend on any sandbox rule.
  mkHookScript =
    name: file:
    pkgs.writeTextFile {
      inherit name;
      text = builtins.readFile file;
      executable = true;
    };

  protectMainScript = mkHookScript "codex-protect-main.js" ./scripts/protect-main.js;
  qualityGateScript = mkHookScript "codex-quality-gate.js" ./scripts/quality-gate.js;
  blockMainShellScript = mkHookScript "codex-block-main-shell.js" ./scripts/block-main-shell.js;

  # ORDERED. Append at the end; see the contract above.
  hookList = [
    {
      event = "PreToolUse";
      stateEvent = "pre_tool_use";
      matcher = "Edit|Write";
      basename = "protect-main.js";
      script = protectMainScript;
      timeout = 5;
    }
    {
      event = "Stop";
      stateEvent = "stop";
      matcher = null;
      basename = "quality-gate.js";
      script = qualityGateScript;
      timeout = 5;
    }
    # APPENDED AT THE END OF THE LIST, 2026-09-10, and that is the whole point:
    # it becomes PreToolUse GROUP 1, so protect-main keeps pre_tool_use:0:0 and
    # quality-gate keeps stop:0:0 — both stay trusted. Inserting it above
    # protect-main would have un-trusted the guard it is meant to reinforce,
    # in silence. Physical position in this list is what decides the group
    # index of a PreToolUse hook; the Stop entry in between changes nothing.
    #
    # WHY IT EXISTS. protect-main only ever sees `Edit|Write`. Measured on a
    # throwaway repo on master: Codex changed a file with
    # `perl -0pi -e 's/1/2/g' note.txt` — a shell command, no edit tool, no
    # hook, no protection. This is the shell half of the same guard, ported
    # from home/claude-code/hooks.nix:hookBlockMainBash.
    #
    # THE MATCHER NAMES THREE TOOLS BECAUSE THE TOOL NAME IS NOT ESTABLISHED.
    # The Codex binary carries the strings `shell`, `local_shell` and `bash`
    # and nothing says which one a PreToolUse payload actually carries. A
    # matcher that guesses wrong produces a hook that never fires — the exact
    # failure being repaired — so all three are named. Same alternation syntax
    # as the `Edit|Write` entry above. The script defends the same way one
    # layer down: it reads the command from every plausible field and accepts
    # a string or an argv array.
    {
      event = "PreToolUse";
      stateEvent = "pre_tool_use";
      matcher = "shell|local_shell|bash";
      basename = "block-main-shell.js";
      script = blockMainShellScript;
      timeout = 5;
    }
  ];

  # First-seen order of the events, taken from the list itself rather than
  # from attribute names, for the same anti-sorting reason.
  eventsInOrder = builtins.foldl' (
    acc: h: if builtins.elem h.event acc then acc else acc ++ [ h.event ]
  ) [ ] hookList;

  groupsOf = event: builtins.filter (h: h.event == event) hookList;

  commandOf = h: "${nodeBin} ${h.script}";

  # One group per hook, so the hook index inside a group is always 0. A group
  # carrying several hooks would need the same imap0 treatment as the groups.
  groupJson =
    h:
    (if h.matcher == null then { } else { inherit (h) matcher; })
    // {
      hooks = [
        {
          type = "command";
          command = commandOf h;
          inherit (h) timeout;
        }
      ];
    };

  hooksJson = builtins.toJSON {
    hooks = builtins.listToAttrs (
      map (e: {
        name = e;
        value = map groupJson (groupsOf e);
      }) eventsInOrder
    );
  };

  # Second output of the same expression: `<snake_event>:<group>:<hook>`.
  trustKeySuffixes = builtins.concatMap (
    e: pkgs.lib.imap0 (i: g: "${g.stateEvent}:${toString i}:0") (groupsOf e)
  ) eventsInOrder;

  # The absolute hooks.json path is the caller's to supply — activation passes
  # a literal "$HOME/..." that the activation shell expands.
  trustKeysFor = hooksPath: map (s: "${hooksPath}:${s}") trustKeySuffixes;

  # What home/codex.nix installs. Derived from the same list, so a hook can
  # never be registered without its script being installed.
  scriptFiles = map (h: {
    target = ".codex/hooks/${h.basename}";
    source = h.script;
  }) hookList;
in
{
  inherit
    nodeBin
    hookList
    hooksJson
    trustKeySuffixes
    trustKeysFor
    scriptFiles
    ;
}
