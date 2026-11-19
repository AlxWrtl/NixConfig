# code-metrics — Uncle Bob's dryer, crapper and mutator on the files a branch
# changed, packaged as a real binary on PATH (skill `code-metrics`, TTW `-m`).
#
# The three tools are pinned non-flake inputs. `code-metrics setup` (outside
# the sandbox, network) copies them into ~/.cache/code-metrics and installs
# them into one venv; mutator imports crapper from that venv. The stamp
# holds their store paths, so a bumped pin asks for setup again.
#
# code-metrics-filter (stdlib) sits between the tools and the wrapper; its
# behaviour is pinned by checks/code-metrics.nix. writePython3Bin runs flake8
# and writeShellApplication runs ShellCheck at build time.
{
  pkgs,
  crapper,
  mutator,
  dryer,
}:
let
  codeMetricsFilterPkg = pkgs.writers.writePython3Bin "code-metrics-filter" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/code-metrics-filter.py);
in
{
  inherit codeMetricsFilterPkg;
  codeMetricsPkg = pkgs.writeShellApplication {
    name = "code-metrics";
    runtimeInputs = [
      pkgs.python3
      pkgs.git
      pkgs.coreutils
      pkgs.gnugrep
      codeMetricsFilterPkg
    ];
    text =
      builtins.replaceStrings
        [ "@CRAPPER@" "@MUTATOR@" "@DRYER@" ]
        [ "${crapper}" "${mutator}" "${dryer}" ]
        (builtins.readFile ./scripts/code-metrics.sh);
  };
}
