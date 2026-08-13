# User-level rules (~/.claude/rules/*.md), loaded BEFORE project rules.
#
# Frontmatter supports exactly one documented field: `paths` (list of globs).
# With `paths` the rule is loaded ON DEMAND, when a matching file is read —
# not at launch, and NOT re-injected after /compact. Only put here what is
# scopable by file type; anything that must always hold stays in CLAUDE.md.
{
  ruleNix = ''
    ---
    paths: ["**/*.nix", "**/flake.lock"]
    ---

    # Nix

    ## Verify
    - `nix-instantiate --parse file.nix && sudo darwin-rebuild switch --flake .#alex-mbp`

    ## Confidence Gate
    - Rate confidence before writing nix. < 80% → STOP, load nix-darwin skill,
      check docs first. 80-95% → state assumptions inline, proceed with caution.
  '';

  ruleTypescript = ''
    ---
    paths: ["**/*.{ts,tsx,js,jsx}", "**/package.json", "**/tsconfig.json"]
    ---

    # TypeScript / JavaScript

    ## Verify
    - `pnpm typecheck && pnpm lint --max-warnings 0`

    ## Rules
    - Package manager: pnpm (never npm or yarn). WCAG AA accessibility minimum.
  '';
}
