# Guard for the self-hosted GitHub Actions runner `browser-macos`
# (modules/github-runner.nix), on the REAL evaluated darwin config.
#
# Evaluation-time check: a `runCommand … exit 1` would not run under
# `--no-build`, so the failures are computed here and `throw`n when non-empty.
# Every attribute access is guarded: a missing daemon or user is a failure
# line, never an evaluation error. The runner executes CI code on this Mac,
# so each invariant closes a path from a job to the host or to the PAT:
#
# 1. The launchd daemon `github-runner-browser-macos` exists.
# 2. The daemon runs as root (no UserName, or "root"): only root may read the
#    PAT. Exactly one line names Runner.Listener; it carries `sudo -u
#    _github-runner` BEFORE the call (a bare call would run job code as
#    root), `/usr/bin/env` HOME= RUNNER_ROOT= RUSTUP_HOME= CARGO_HOME= PATH=
#    (sudo resets the environment) and `--jitconfig`. run.sh lines get the
#    same sudo/env test. Comment lines are skipped, `\` continuations are
#    joined first.
# 3. User/group `_github-runner` uid/gid 533, home /var/lib/github-runners,
#    createHome false, declared in knownUsers/knownGroups (nix-darwin only
#    creates and deletes known ones).
# 4. KeepAlive is exactly { SuccessfulExit = true; } (null keys dropped):
#    launchd ORs its keys, so `Crashed = false` respawns every non-crash exit
#    and `exit 78` (no token) would loop. ThrottleInterval >= 30, RunAtLoad.
# 5. The runner is a just-in-time one (single job, so ephemeral by
#    construction): the script POSTs to generate-jitconfig on the literal
#    AlxWrtl/browser API URL with exactly one label, `["browser-macos"]`
#    (`browser-mac` is the Linux label: a typo sends the job elsewhere).
#    Every curl line reads its config (the Authorization header) from stdin,
#    `--config -`, and passes no Authorization nor `$token` after `curl`: the
#    PAT never enters an argv. No `--pat`, `--token` nor `config.sh`
#    anywhere. `exit 78` on a code line. Flags count only on code lines:
#    comments and plain echo/printf messages are stripped first.
# 6. Every https://github.com/OWNER/REPO or https://api.github.com/repos/
#    OWNER/REPO in the script is AlxWrtl/browser and every `github.com/`
#    occurrence is such a parsed URL (a `$var` URL would escape the
#    comparison). None names a public repo: a fork's pull request would run
#    on this Mac. An EMPTY URL list is a failure, not a pass.
# 7. The token file /var/lib/github-runners/browser-macos.token is named in
#    the script and in WatchPaths, lives outside the store (world-readable)
#    and outside the runner state dir (wiped and owned by _github-runner).
#    No store path names the PAT or the token, no literal `github_pat_`.
# 8. The activation slice between the BEGIN/END markers in
#    activationScripts.launchd (the only named slot run before the daemons
#    load) is non-empty, copies the PAT from ~/.config/secrets with
#    `-m 0400 -o root` and without `-g _github-runner` (jobs must never read
#    it), warns with `warning:` when it is absent, and holds no `exit` nor
#    `return` (one `set -e` shell: either kills every later step) and no
#    `|| true` nor `|| :`. Root never mkdir/chown/chmods a path INSIDE a
#    runner-owned dir (state, work, cache: a job shapes that tree), and its
#    chown/chmod on those dirs carry `-h` and no `-R`.
# 9. HOME = RUNNER_ROOT = the state dir, RUSTUP_HOME under the shared cache
#    /var/lib/github-runners/_cache/ (the state dir is wiped per job); the
#    daemon PATH holds /usr/bin (cc from the CLT) and a rustup store path.
{
  pkgs,
  darwin,
}:

let
  inherit (pkgs) lib;

  name = "github-runner-browser-macos";
  account = "_github-runner";
  stateDir = "/var/lib/github-runners/browser-macos";
  cacheDir = "/var/lib/github-runners/_cache/";
  runnerDirs = [
    stateDir
    "/var/lib/github-runners/_work/browser-macos"
    "${cacheDir}browser-macos"
  ];
  tokenFile = "/var/lib/github-runners/browser-macos.token";
  patSource = ".config/secrets/github-runner-browser-pat";
  repo = "AlxWrtl/browser";
  jitUrl = "https://api.github.com/repos/${repo}/actions/runners/generate-jitconfig";
  # Extend with the public holbertonschool-* repos.
  publicRepos = [
    "NixConfig"
    "apex-skill"
  ];
  sudoAs = "sudo -u ${account}";
  beginMarker = "# ${name} BEGIN";
  endMarker = "# ${name} END";
  storeDir = builtins.storeDir;

  daemon = (darwin.launchd.daemons or { }).${name} or null;
  sc = if daemon == null then { } else daemon.serviceConfig or { };
  script = if daemon == null then "" else daemon.script or "";
  daemonPath = if daemon == null then "" else daemon.path or "";
  user = (darwin.users.users or { }).${account} or null;
  group = (darwin.users.groups or { }).${account} or null;
  knownUsers = darwin.users.knownUsers or [ ];
  knownGroups = darwin.users.knownGroups or [ ];
  ka = sc.KeepAlive or null;
  kaSet = if builtins.isAttrs ka then lib.filterAttrs (_: v: v != null) ka else ka;
  throttle = sc.ThrottleInterval or null;
  watchPaths = if builtins.isList (sc.WatchPaths or null) then sc.WatchPaths else [ ];

  activationText = ((darwin.system.activationScripts or { }).launchd or { }).text or "";
  afterBegin = lib.splitString beginMarker activationText;
  slice =
    if builtins.length afterBegin != 2 then
      ""
    else
      let
        rest = lib.splitString endMarker (builtins.elemAt afterBegin 1);
      in
      if builtins.length rest < 2 then "" else builtins.head rest;

  # `\`-continued commands become one line before any per-line test.
  logicalLines = s: lib.splitString "\n" (builtins.replaceStrings [ "\\\n" ] [ " " ] s);
  isComment = l: builtins.match "[[:space:]]*#.*" l != null;
  scriptLines = builtins.filter (l: !isComment l) (logicalLines script);
  sliceLines = builtins.filter (l: !isComment l) (logicalLines slice);
  # A plain message: echo/printf without pipe, list or substitution.
  isMessage =
    l:
    builtins.match "[[:space:]]*(echo|printf)([[:space:]].*)?" l != null
    && builtins.match ".*(\\||;|&&|\\$\\(|`).*" l == null;
  # Presence tests only: a trailing ` # …` is cut, so a flag in it is absent.
  flagLines = map (l: builtins.head (builtins.split "[[:space:]]#" l)) (
    builtins.filter (l: !isMessage l) scriptLines
  );
  flagText = builtins.concatStringsSep "\n" flagLines;

  # Number of non-overlapping matches of `re` in `s`.
  count = re: s: (builtins.length (builtins.split re s) - 1) / 2;
  # `name=` as a whole word: CARGO_HOME= must not count as HOME=.
  setsVar = var: l: builtins.match "(.*[^A-Za-z0-9_])?${var}=.*" l != null;
  hasWord = w: l: builtins.match "(.*[^A-Za-z0-9_])?${w}([^A-Za-z0-9_].*)?" l != null;

  invocations = tok: builtins.filter (lib.hasInfix tok) scriptLines;
  sudoBefore = tok: l: lib.hasInfix sudoAs (builtins.head (lib.splitString tok l));
  envVars = [
    "HOME"
    "RUNNER_ROOT"
    "RUSTUP_HOME"
    "CARGO_HOME"
    "PATH"
  ];
  launchFailures =
    tok: required:
    let
      ls = invocations tok;
    in
    lib.optional (required && ls == [ ]) "script never invokes ${tok} (expected through `${sudoAs}`)"
    ++ map (l: "script invokes ${tok} without `${sudoAs}` before it: ${lib.strings.trim l}") (
      builtins.filter (l: !(sudoBefore tok l)) ls
    )
    ++ lib.concatMap (
      l:
      lib.optional (
        !(lib.hasInfix "/usr/bin/env" l)
      ) "${tok} line lacks /usr/bin/env (sudo resets the environment): ${lib.strings.trim l}"
      ++ map (v: "${tok} line does not pass ${v}= through sudo: ${lib.strings.trim l}") (
        builtins.filter (v: !(setsVar v l)) envVars
      )
    ) (builtins.filter (sudoBefore tok) ls);

  listenerLines = invocations "Runner.Listener";
  afterFirst = tok: l: builtins.concatStringsSep tok (builtins.tail (lib.splitString tok l));
  curlLines = builtins.filter (hasWord "curl") scriptLines;
  hasFlagWith =
    c: l: builtins.match "(.*[[:space:]])?-[A-Za-z]*${c}[A-Za-z]*([[:space:]].*)?" l != null;

  labelWords = count "[^A-Za-z0-9_]labels[^A-Za-z0-9_]" (
    "\n" + builtins.concatStringsSep "\n" scriptLines + "\n"
  );
  labelExact =
    count
      "[^A-Za-z0-9_]labels\"?[[:space:]]*:[[:space:]]*[[][[:space:]]*\"browser-macos\"[[:space:]]*[]][[:space:]]*[,}]"
      ("\n" + flagText);

  rootOps = builtins.filter (
    l:
    builtins.any (w: hasWord w l) [
      "chown"
      "chmod"
      "mkdir"
    ]
  ) sliceLines;
  namesDir =
    d: l: builtins.match "(.*[[:space:]\"'])?${lib.escapeRegex d}/?([[:space:]\"';].*)?" l != null;
  insideRunnerDir = l: builtins.any (d: lib.hasInfix "${d}/" l) runnerDirs;
  runnerDirOps = builtins.filter (
    l: (hasWord "chown" l || hasWord "chmod" l) && builtins.any (d: namesDir d l) runnerDirs
  ) sliceLines;

  urlRe = "https://(github\\.com|api\\.github\\.com/repos)/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)";
  urls = map (m: lib.removeSuffix ".git" (builtins.elemAt m 1)) (
    builtins.filter builtins.isList (builtins.split urlRe script)
  );
  githubMentions = count "[^A-Za-z0-9-]github\\.com/" ("\n" + script);

  # Every `VAR=` assignment in the script must have this exact value shape.
  assignments = var: count "[^A-Za-z0-9_]${var}=" ("\n" + script);
  assignedTo = var: valueRe: count "[^A-Za-z0-9_]${var}=[\"']?${valueRe}" ("\n" + script);
  stateDirValue = "${stateDir}([\"'[:space:];]|$)";
  cacheValue = "${cacheDir}[A-Za-z0-9_.-]";

  leakRe = "${storeDir}/[a-z0-9]{32}-[^[:space:]\"']*(github-runner-browser-pat|browser-macos\\.token)";
  everything = script + "\n" + slice + "\n" + builtins.concatStringsSep "\n" watchPaths;
  tokenLines = builtins.filter (l: lib.hasInfix "-m 0400" l || lib.hasInfix "browser-macos.token" l) (
    builtins.filter (l: lib.hasInfix "install" l || lib.hasInfix "-m 0" l) sliceLines
  );

  failures =
    # 1
    lib.optional (daemon == null) "launchd daemon ${name} is missing"
    # 2
    ++
      lib.optional
        (
          !(builtins.elem (sc.UserName or null) [
            null
            "root"
          ])
        )
        "daemon UserName is ${
          builtins.toJSON (sc.UserName or null)
        }, expected unset or root (only root may read the PAT)"
    ++ launchFailures "Runner.Listener" true
    ++ launchFailures "run.sh" false
    ++
      lib.optional (builtins.length listenerLines > 1)
        "script names Runner.Listener on ${toString (builtins.length listenerLines)} lines, expected exactly one"
    ++ map (l: "Runner.Listener line lacks --jitconfig after the call: ${lib.strings.trim l}") (
      builtins.filter (l: !(lib.hasInfix "--jitconfig" (afterFirst "Runner.Listener" l))) listenerLines
    )
    # 3
    ++ lib.optional (user == null) "users.users.${account} is missing"
    ++ lib.optional (user != null && (user.uid or null) != 533) "users.users.${account}.uid must be 533"
    ++ lib.optional (user != null && (user.gid or null) != 533) "users.users.${account}.gid must be 533"
    ++ lib.optional (
      user != null && (user.home or null) != "/var/lib/github-runners"
    ) "users.users.${account}.home must be /var/lib/github-runners"
    ++ lib.optional (
      user != null && (user.createHome or null) != false
    ) "users.users.${account}.createHome must be false"
    ++ lib.optional (!(builtins.elem account knownUsers)) "users.knownUsers lacks ${account}"
    ++ lib.optional (!(builtins.elem account knownGroups)) "users.knownGroups lacks ${account}"
    ++ lib.optional (group == null) "users.groups.${account} is missing"
    ++ lib.optional (
      group != null && (group.gid or null) != 533
    ) "users.groups.${account}.gid must be 533"
    # 4
    ++
      lib.optional (kaSet != { SuccessfulExit = true; })
        "serviceConfig.KeepAlive must be exactly { SuccessfulExit = true; }, got ${builtins.toJSON kaSet} (keys are ORed: any other key respawns exit 78)"
    ++
      lib.optional (builtins.isAttrs kaSet && kaSet ? Crashed)
        "serviceConfig.KeepAlive sets Crashed (Crashed = false respawns every non-crash exit, exit 78 included)"
    ++ lib.optional (
      !(builtins.isInt throttle && throttle >= 30)
    ) "serviceConfig.ThrottleInterval must be >= 30"
    ++ lib.optional ((sc.RunAtLoad or null) != true) "serviceConfig.RunAtLoad must be true"
    # 5
    ++ lib.optional (
      !(builtins.any (l: lib.hasInfix jitUrl l) (builtins.filter (hasWord "curl") flagLines))
    ) "script has no curl code line on ${jitUrl}"
    ++ map (l: "curl line does not read its config from stdin (`--config -`): ${lib.strings.trim l}") (
      builtins.filter (
        l: builtins.match ".*[[:space:]]--config[[:space:]]+-([[:space:]].*)?" l == null
      ) curlLines
    )
    ++ map (l: "curl line passes Authorization or $token in its argv: ${lib.strings.trim l}") (
      builtins.filter (
        l:
        let
          a = afterFirst "curl" l;
        in
        lib.hasInfix "Authorization" a || lib.hasInfix "$token" a || lib.hasInfix "\${token" a
      ) curlLines
    )
    ++
      lib.optional (labelWords != 1 || labelExact != 1)
        "script must hold exactly one `labels: [\"browser-macos\"]` on a code line (found ${toString labelWords} labels, ${toString labelExact} exact)"
    ++
      map (f: "script contains ${f} (the PAT must only reach generate-jitconfig through curl's stdin)")
        (
          builtins.filter (f: lib.hasInfix f script) [
            "--pat"
            "--token"
            "config.sh"
          ]
        )
    ++ lib.optional (
      !(builtins.any (
        l: builtins.match "(.*[^A-Za-z0-9_])?exit[[:space:]]+78([^0-9].*)?" l != null
      ) flagLines)
    ) "script lacks `exit 78` on a code line"
    # 6
    ++ lib.optional (
      urls == [ ]
    ) "script holds no https://github.com/OWNER/REPO URL (the repo comparison would pass vacuously)"
    ++ map (u: "script names github.com/${u}, expected only ${repo}") (
      builtins.filter (u: u != repo) urls
    )
    ++
      lib.optional (githubMentions != builtins.length urls)
        "script has ${toString githubMentions} github.com/ mentions but ${toString (builtins.length urls)} literal OWNER/REPO URLs: every URL must be literal"
    ++ map (r: "script names the public repo ${r}: a fork's pull request would run on this Mac") (
      builtins.filter (
        r: lib.hasInfix "/${r}" script || builtins.elem r (map (u: lib.last (lib.splitString "/" u)) urls)
      ) publicRepos
    )
    # 7
    ++ lib.optional (
      !(lib.hasInfix tokenFile script)
    ) "script does not name the token file ${tokenFile}"
    ++ lib.optional (
      !(builtins.elem tokenFile watchPaths)
    ) "serviceConfig.WatchPaths lacks ${tokenFile} (the daemon would not start when the PAT lands)"
    ++ lib.optional (lib.hasPrefix "${storeDir}/" tokenFile) "token file is under the store"
    ++ lib.optional (lib.hasPrefix "${stateDir}/" tokenFile) "token file is under the runner state dir"
    ++ map (p: "WatchPaths entry ${p} is under the store or the runner state dir") (
      builtins.filter (p: lib.hasPrefix "${storeDir}/" p || lib.hasPrefix "${stateDir}/" p) watchPaths
    )
    ++ lib.optional (count leakRe everything > 0) "a store path names the PAT or the token file"
    ++ lib.optional (lib.hasInfix "github_pat_" everything) "a literal github_pat_ appears in the config"
    # 8
    ++ lib.optional (
      lib.strings.trim slice == ""
    ) "activationScripts.launchd has no non-empty slice between `${beginMarker}` and `${endMarker}`"
    ++ lib.optional (!(lib.hasInfix patSource slice)) "activation slice does not read ~/${patSource}"
    ++ lib.optional (
      !(lib.hasInfix "warning:" slice)
    ) "activation slice has no `warning:` for a missing PAT"
    ++ lib.optional (
      !(builtins.any (l: lib.hasInfix "-m 0400" l && lib.hasInfix "-o root" l) sliceLines)
    ) "activation slice has no token copy with `-m 0400 -o root`"
    ++ lib.optional (lib.hasInfix "-m 0440" slice) "activation slice uses -m 0440 (the token must be root-only)"
    ++ map (l: "token line grants the group ${account}: ${lib.strings.trim l}") (
      builtins.filter (lib.hasInfix "-g ${account}") tokenLines
    )
    ++ lib.optional (builtins.any (hasWord "exit") (logicalLines slice)) "activation slice contains `exit` (kills every later activation step)"
    ++ lib.optional (count "\\|\\|[[:space:]]*true" slice > 0) "activation slice contains `|| true`"
    ++ lib.optional (count "\\|\\|[[:space:]]*:" slice > 0) "activation slice contains `|| :`"
    ++ lib.optional (builtins.any (hasWord "return") (logicalLines slice)) "activation slice contains `return` (kills every later activation step)"
    ++ map (
      l: "activation slice: root mkdir/chown/chmod inside a runner-owned dir: ${lib.strings.trim l}"
    ) (builtins.filter insideRunnerDir rootOps)
    ++ map (
      l: "activation slice: chown/chmod on a runner-owned dir without `-h`: ${lib.strings.trim l}"
    ) (builtins.filter (l: !(hasFlagWith "h" l)) runnerDirOps)
    ++ map (l: "activation slice: recursive chown/chmod on a runner-owned dir: ${lib.strings.trim l}") (
      builtins.filter (hasFlagWith "R") runnerDirOps
    )
    # 9
    ++
      lib.concatMap
        (
          v:
          lib.optional (assignments v == 0) "script never sets ${v}="
          ++ lib.optional (
            assignments v != assignedTo v stateDirValue
          ) "every ${v}= in the script must be exactly ${stateDir}"
        )
        [
          "HOME"
          "RUNNER_ROOT"
        ]
    ++ lib.optional (assignments "RUSTUP_HOME" == 0) "script never sets RUSTUP_HOME="
    ++ lib.optional (
      assignments "RUSTUP_HOME" != assignedTo "RUSTUP_HOME" cacheValue
    ) "every RUSTUP_HOME= in the script must be under ${cacheDir} (the state dir is wiped per job)"
    ++ lib.optional (
      !(builtins.elem "/usr/bin" (lib.splitString ":" daemonPath))
    ) "daemon path lacks /usr/bin"
    ++ lib.optional (
      builtins.match ".*${storeDir}/[a-z0-9]{32}-rustup-.*" daemonPath == null
    ) "daemon path lacks a rustup store path";
in
if failures != [ ] then
  throw ("github-runner:\n  - " + builtins.concatStringsSep "\n  - " failures)
else
  pkgs.runCommand "check-github-runner" { } "touch $out"
