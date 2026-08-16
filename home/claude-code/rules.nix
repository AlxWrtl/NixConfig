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

    ## Docs before writing
    - Confidence < 80% on a library API → `libdocs <name> "<question>"` BEFORE
      writing. `libdocs --list` shows the pinned names.
    - Ids are pinned per MAJOR version because doc search ranks the OLD major
      higher: Tailwind v3 outweighs v4, Zod v3 outweighs v4 by 4.5x. Never
      resolve a library by raw search when a pin exists.

    ## Version traps in this stack
    - Tailwind v4 is CSS-first: `@import "tailwindcss"` + `@theme`. No
      `tailwind.config.js`, no `@tailwind base/components/utilities`.
    - Zod 4: top-level validators — `z.email()`, not `z.string().email()`.
    - date-fns 4: `TZDate` from `@date-fns/tz`, not `utcToZonedTime`.
    - Vite 7 here; upstream main is already v8 — check before using a new API.
  '';

  # Stack: React 19 + React Router 7 + TypeScript. Narrower `paths` than
  # ruleTypescript on purpose — both load on a .tsx, and this one carries the
  # cost only where React is actually written.
  ruleReact = ''
    ---
    paths: ["**/*.{tsx,jsx}"]
    ---

    # React 19 + React Router 7

    ## Confidence Gate — before writing, not after
    - Rate confidence on any API, signature or version detail BEFORE writing.
      < 80% → STOP, run `libdocs`, then write. Never guess a signature.
      `libdocs react "<question>"` · `libdocs rr "<question>"` · `libdocs --list`
    - Version trap: ranking doc hits by score or corpus size puts React Router
      v5 ABOVE v7. Use the pinned names (`react`, `rr`), never a raw search hit.

    ## Verify
    - `pnpm typecheck && pnpm lint --max-warnings 0`
    - `eslint-plugin-react-hooks` must be enabled: it machine-checks what the
      docs only describe. Docs before writing, lint after — both, not either.

    ## Anti-patterns (blocking)
    - `useEffect` to derive state from props/state → compute during render.
    - `useEffect` to notify a parent of a state change → call the handler in
      the event, not in an effect.
    - Index as list `key` on a reordered or filtered list → stable identity key.
    - `react-router-dom` imports → in v7 the package is `react-router`.

    ## React 19 / RR7 specifics
    - Async form state: `useActionState`, `useOptimistic`, `use()`.
      `useFormState` is the v18 name — do not write it.
    - Server Components take no hooks and no browser APIs; the boundary is
      explicit. Check it with `libdocs` before crossing it.
    - Routes are declared in `routes.ts` (framework mode), loaders per route.
  '';
}
