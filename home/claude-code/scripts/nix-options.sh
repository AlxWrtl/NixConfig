# nix-options — nix-darwin + home-manager option docs at the flake.lock rev.
# (writeShellApplication prepends set -euo pipefail and shellchecks at build.)
#
# Replaces the static Nix-Darwin-Doc.md: instead of a snapshot that drifts,
# evaluate the option declarations of the modules the flake actually pins
# (nix-darwin, home-manager, determinate, nixpkgs lib) and map each
# "declared in" path to GitHub at the locked rev.
#
# Contract:
#   - User input NEVER enters the Nix expression: the --apply body below is a
#     constant. Option paths and regexes only reach jq through --arg; host and
#     flake are validated before being spliced into the installable.
#   - ONE eval per run: lazy-trees virtual store prefixes change per eval, so
#     the anchors that map a declaration to its input come from the same call.
#   - Plain eval first. Inside the Claude sandbox the daemon socket is denied:
#     only on that class of error, retry against a read-only local store with a
#     private XDG_CACHE_HOME. Any other failure is printed as-is.
#   - Exit codes: 0 found, 1 no match, 2 usage, 3 nix/eval/environment.

HOST_DEFAULT="alex-mbp"

usage() {
  cat <<'EOF'
nix-options — nix-darwin + home-manager option docs at the flake.lock rev

Usage:
  nix-options [--flake PATH] [--host NAME] [--json] show <option.path>
  nix-options [--flake PATH] [--host NAME] [--json] search <regex>

  show     exact option; home-manager.users.<user>.X looks up X in home-manager
  search   case-insensitive regex (jq) on option names, nix-darwin then home-manager
  --flake  flake directory (default: $NIX_OPTIONS_FLAKE, else ~/.config/nix-darwin)
  --host   darwinConfigurations attribute (default: alex-mbp)
  --json   machine-readable output

Exit: 0 found, 1 no match, 2 usage, 3 nix/eval failure.
EOF
}

usage_error() {
  printf 'nix-options: %s\n' "$1" >&2
  usage >&2
  exit 2
}

flake="${NIX_OPTIONS_FLAKE:-$HOME/.config/nix-darwin}"
host="$HOST_DEFAULT"
json=0
positional=()

while (($# > 0)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --json)
      json=1
      shift
      ;;
    --flake | --host)
      (($# >= 2)) || usage_error "$1 needs a value"
      if [[ $1 == --flake ]]; then flake="$2"; else host="$2"; fi
      shift 2
      ;;
    --flake=*)
      flake="${1#--flake=}"
      shift
      ;;
    --host=*)
      host="${1#--host=}"
      shift
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    -*) usage_error "unknown flag: $1" ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

((${#positional[@]} == 2)) || usage_error "expected a subcommand and one argument"
cmd="${positional[0]}"
query="${positional[1]}"
case "$cmd" in
  show | search) ;;
  *) usage_error "unknown subcommand: $cmd" ;;
esac
[[ -n $query && $query =~ ^[[:graph:]]+$ ]] || usage_error "argument must be non-empty, without spaces"

[[ $host =~ ^[A-Za-z0-9_-]+$ ]] || usage_error "invalid --host: $host"
[[ -d $flake && -f $flake/flake.nix && -f $flake/flake.lock ]] ||
  usage_error "not a flake directory (flake.nix + flake.lock): $flake"
flake="$(cd "$flake" && pwd -P)"
[[ $flake != *[#?]* ]] || usage_error "flake path must not contain '#' or '?': $flake"

if [[ $cmd == search ]] && ! jq -n --arg re "$query" '"" | test($re; "i")' >/dev/null 2>&1; then
  printf 'nix-options: invalid regex: %s\n' "$query" >&2
  jq -n --arg re "$query" '"" | test($re; "i")' 2>&1 >/dev/null | sed 's/^/  /' >&2 || true
  exit 2
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "nix-options: nix not found on PATH (expected the system Determinate nix)" >&2
  exit 3
fi

work=""
cleanup() {
  if [[ -n $work ]]; then rm -rf "$work"; fi
}
trap cleanup EXIT
work="$(mktemp -d "${TMPDIR:-/tmp}/nix-options.XXXXXX")"

# Constant: no shell interpolation (quoted heredoc). Anchors = one option per
# input whose declaration path yields that input's virtual store prefix.
expr="$(
  cat <<'EOF'
c: let
  lib = c.pkgs.lib;
  o = c.options;
  hm = o.home-manager.users.type.getSubOptions [ ];
  pre = d: if d == [ ] then null else let m = builtins.match "(/nix/store/[^/]+)/.*" (builtins.head d); in if m == null then null else builtins.head m;
  keep = l: map (x: { inherit (x) name description type declarations; default = x.default or null; example = x.example or null; readOnly = x.readOnly or false; })
    (builtins.filter (x: (x.visible or true) != false && !(x.internal or false)) l);
in {
  anchors = {
    nix-darwin = pre (o.system.defaults.dock.autohide.declarations or [ ]);
    home-manager = pre (o.home-manager.users.declarations or [ ]);
    determinate = pre (o.determinateNix.enable.declarations or [ ]);
    nixpkgs = pre (hm.meta.maintainers.declarations or [ ]);
  };
  darwin = keep (lib.optionAttrSetToDocList o);
  hm = keep (lib.optionAttrSetToDocList hm);
}
EOF
)"

installable="$flake#darwinConfigurations.$host"
raw="$work/eval.json"
err="$work/eval.err"

if ! nix eval --json "$installable" --apply "$expr" >"$raw" 2>"$err"; then
  if grep -Eq 'daemon-socket|Operation not permitted|readonly database|read-only file system' "$err"; then
    cache="$(mktemp -d "$work/xdg-cache.XXXXXX")"
    if ! XDG_CACHE_HOME="$cache" nix eval --json \
      --store 'local?read-only=true' --extra-experimental-features read-only-local-store \
      "$installable" --apply "$expr" >"$raw" 2>"$err"; then
      echo "nix-options: eval failed (daemon unreachable, read-only store retry failed too):" >&2
      cat "$err" >&2
      exit 3
    fi
  else
    echo "nix-options: eval failed:" >&2
    cat "$err" >&2
    exit 3
  fi
fi

# Normalise: display name, source tag, declarations mapped to GitHub at the
# flake.lock rev; anything that cannot be mapped stays raw + " (unmapped)".
normalize="$(
  cat <<'EOF'
$lockf[0] as $lock
| def lockurl($input; $suffix):
  ($lock.nodes.root.inputs[$input]) as $k
  | if ($k | type) != "string" then null
    else ($lock.nodes[$k].locked // {}) as $l
      | if $l.type == "github" and $l.owner and $l.repo and $l.rev then
          "https://github.com/\($l.owner)/\($l.repo)/blob/\($l.rev)/\($suffix)"
        elif $l.type == "tarball" and $l.rev and (($l.url // "") | test("/f/pinned/[^/]+/[^/]+/")) then
          ($l.url | capture("/f/pinned/(?<o>[^/]+)/(?<r>[^/]+)/")) as $c
          | "https://github.com/\($c.o)/\($c.r)/blob/\($l.rev)/\($suffix)"
        else null end
    end;
def mapdecl($anchors):
  . as $d
  | ( if ($d | startswith("/")) then
        first($anchors[] as $a | select($d | startswith($a.value + "/"))
              | lockurl($a.key; $d[($a.value | length) + 1:])) // null
      else lockurl("nixpkgs"; $d) end
    ) // ($d + " (unmapped)");
def val: if type == "object" and has("_type") then .text else . end;
(.anchors | to_entries | map(select(.value != null))) as $anchors
| [ (.darwin[] | {source: "darwin"} + .),
    (.hm[] | {source: "hm"} + . + {name: (.name | sub("^<name>\\."; ""))}) ]
| map({source, name, type,
       default: (.default | val), example: (.example | val),
       readOnly: (.readOnly == true),
       declarations: [(.declarations // [])[] | tostring | mapdecl($anchors)],
       description})
EOF
)"
all="$work/all.json"
if ! jq --slurpfile lockf "$flake/flake.lock" "$normalize" "$raw" >"$all"; then
  echo "nix-options: failed to process eval output" >&2
  exit 3
fi

if [[ $cmd == search ]]; then
  res="$work/search.json"
  jq --arg re "$query" '
    [ .[] | select(.name | test($re; "i"))
      | {source, name,
         summary: ((.description // "") | sub("^\\s+"; "") | split("\n")[0] | .[0:100])} ]
  ' "$all" >"$res"
  if [[ $(jq length "$res") == 0 ]]; then
    printf "nix-options: no option matches /%s/ (case-insensitive) in nix-darwin or home-manager\n" "$query" >&2
    exit 1
  fi
  if ((json)); then
    jq . "$res"
  else
    jq -r '.[] | "\(.name)\(if .source == "hm" then "  [hm]" else "" end) — \(.summary)"' "$res"
  fi
  exit 0
fi

# show
name="$query"
hmonly=0
if [[ $name =~ ^home-manager\.users\.[^.]+\.(.+)$ ]]; then
  name="${BASH_REMATCH[1]}"
  hmonly=1
fi

res="$work/show.json"
jq --arg p "$name" --argjson hmonly "$hmonly" \
  '[ .[] | select(.name == $p and ($hmonly == 0 or .source == "hm")) ]' "$all" >"$res"

if [[ $(jq length "$res") == 0 ]]; then
  printf "nix-options: no option '%s' in nix-darwin or home-manager (flake %s, host %s)\n" \
    "$query" "$flake" "$host" >&2
  if jq -e --arg p "$name" 'any(.[]; .name | startswith($p + "."))' "$all" >/dev/null; then
    printf "'%s' is not a leaf; try: nix-options search '^%s\\.'\n" "$name" "${name//./\\.}" >&2
  fi
  near="$(jq -r --arg p "$name" '
    ($p | split(".") | last | ascii_downcase) as $l
    | ($p | split(".") | .[:-1] | join(".")) as $parent
    | (if ($l | length) <= 3 then [$l] else [range($l | length; 2; -1) as $n | $l[0:$n]] end) as $cands
    | [ .[] | {source, name, low: (.name | ascii_downcase)} ] as $all
    | (first($cands[] as $c | [$all[] | select(.low | contains($c))] | select(length > 0)) // [])
    | sort_by(if $parent != "" and (.name | startswith($parent + ".")) then 0 else 1 end)
    | .[:10][]
    | "  \(.name)\(if .source == "hm" then "  [hm]" else "" end)"
  ' "$all")"
  if [[ -n $near ]]; then
    printf 'Near matches:\n%s\n' "$near" >&2
  fi
  exit 1
fi

if ((json)); then
  jq . "$res"
  exit 0
fi

jq -r '
  def ind: sub("\\s+$"; "") | split("\n") | .[0:1] + (.[1:] | map(if . == "" then . else "    " + . end)) | join("\n");
  def txt: if . == null then "—" elif type == "string" then . else tojson end;
  [ .[]
    | [ "\(.name)  [\(.source)]",
        "  Type: \(.type // "—")",
        "  Default: \(.default | txt | ind)" ]
      + (if .example != null then ["  Example: \(.example | txt | ind)"] else [] end)
      + (if .readOnly then ["  Read-only: yes"] else [] end)
      + ["  Declared in:"] + [.declarations[] | "    \(.)"]
      + ["  Description:", "    \((.description // "—") | ind)"]
    | join("\n") ]
  | join("\n\n")
' "$res"
