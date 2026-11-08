# APEX: Ajouter le cask vorssaint (keep-awake capot fermé)
Tier: Direct
Flags: -pr
Files: modules/brew.nix
Est-lines: 1
Baseline: nix flake check --no-build -> pending

## ACs
- `vorssaint` présent dans `homebrew.casks` (groupe auto-updating, le cask déclare auto_updates)
- `nix flake check --no-build` vert

## Tokens
| Point | Coordinator context |
|-------|---------------------|
| start | 61219 |
| end | |
