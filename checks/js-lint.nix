# ESLint over every tracked JavaScript file of the repo: the Claude hooks under
# home/claude-code/hooks/ and the Codex scripts under home/codex/scripts/.
#
# eslint:recommended is rebuilt from eslint's own `builtinRules`
# (`meta.docs.recommended`): pkgs.eslint ships `globals` but not `@eslint/js`,
# and this check pulls no npm dependency. Two relaxations, both on catch
# blocks only — those are the hooks' deliberate fail-open / fail-closed sites:
# an empty `catch {}` and an unused catch parameter are allowed.
#
# The instrument is proven able to fail before its green is believed: a canary
# file with an unused variable must turn eslint red for that rule, and the
# number of files eslint actually reports on must equal the number found, so
# an ignore pattern or a wrong base path cannot lint nothing and pass.
#
# Runs in `nix flake check`.
{ pkgs }:

let
  inherit (pkgs) lib;
  inherit (pkgs) eslint;

  # Adding or removing a .js file changes this number on purpose: the count is
  # what proves the walk saw every file.
  expectedFiles = 16;

  eslintDir = "${eslint}/lib/node_modules/eslint";

  config = pkgs.writeText "eslint.config.cjs" ''
    "use strict";
    const { builtinRules } = require(${builtins.toJSON "${eslintDir}/lib/unsupported-api.js"});
    const globals = require(${builtins.toJSON "${eslintDir}/node_modules/globals"});
    const rules = {};
    for (const [name, rule] of builtinRules) {
      if (rule.meta && rule.meta.docs && rule.meta.docs.recommended) rules[name] = "error";
    }
    if (Object.keys(rules).length === 0) throw new Error("js-lint: builtinRules yielded no recommended rule");
    rules["no-empty"] = ["error", { allowEmptyCatch: true }];
    rules["no-unused-vars"] = ["error", { caughtErrors: "none" }];
    module.exports = [
      {
        files: ["**/*.js", "**/*.cjs", "**/*.mjs"],
        languageOptions: { ecmaVersion: "latest", sourceType: "commonjs", globals: { ...globals.node } },
        linterOptions: { reportUnusedDisableDirectives: "error" },
        rules,
      },
    ];
  '';

  # The flake source holds tracked files only, so this is every tracked JS file.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.fileFilter (f: f.hasExt "js" || f.hasExt "cjs" || f.hasExt "mjs") ../.;
  };
in
assert lib.assertMsg (lib.versions.major eslint.version == "10")
  "js-lint: written against eslint 10 (flat config, lib/unsupported-api.js); pkgs.eslint is ${eslint.version}";
pkgs.runCommand "check-js-lint"
  {
    nativeBuildInputs = [
      eslint
      pkgs.jq
    ];
  }
  ''
    export HOME="$TMPDIR"
    # eslint resolves files against the cwd, so each run happens in the dir
    # holding both the config and src/. Sets $rc: 0 clean, 1 findings, 2 fatal.
    lint() {
      cp ${config} "$1/eslint.config.cjs"
      rc=0
      (cd "$1" && eslint -f json -o report.json --max-warnings 0 src) || rc=$?
    }
    show() {
      jq -r '.[] | (.filePath | sub(".*/src/"; "")) as $f | .messages[] | "\($f):\(.line):\(.column) \(.ruleId) \(.message)"' "$1/report.json"
    }

    mkdir -p work/src canary/src
    cp -r ${src}/. work/src/
    chmod -R u+w work
    n=$(find work/src -type f \( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' \) | wc -l | tr -d ' ')
    [ "$n" -eq ${toString expectedFiles} ] || {
      echo "js-lint: expected ${toString expectedFiles} JS files, found $n. A file was added or removed: update expectedFiles in checks/js-lint.nix" >&2
      exit 1
    }

    printf '"use strict";\nconst unused = 1;\n' > canary/src/canary.js
    lint canary
    [ "$rc" -eq 1 ] || { echo "js-lint: canary exit $rc, expected 1 — the instrument cannot fail" >&2; exit 1; }
    jq -e 'any(.[].messages[]; .ruleId == "no-unused-vars")' canary/report.json > /dev/null || {
      echo "js-lint: canary went red for the wrong reason:" >&2; show canary >&2; exit 1
    }
    echo "js-lint: canary killed (no-unused-vars)"

    lint work
    linted=$(jq length work/report.json)
    show work
    [ "$linted" -eq "$n" ] || { echo "js-lint: eslint reported on $linted of $n files — some were ignored" >&2; exit 1; }
    [ "$rc" -eq 0 ] || { echo "js-lint: eslint exit $rc" >&2; exit 1; }
    echo "js-lint: $linted files, 0 problems"
    touch "$out"
  ''
