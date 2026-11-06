# Atlas API

These rules apply to the Phoenix/Ash backend. Shared rules are in the root `AGENTS.md`.

## Backend

- Run Mix tasks from `apps/api`.
- Keep application endpoints JSON-only. Application pages and frontend source belong in `apps/web`.
- Approved release exception: `AtlasWeb.Plugs.Frontend` may serve public compiled outputs with
  `SERVE_FRONTEND=true` (default off). Never build frontend assets in Mix or add application LiveViews.
  Preserve reserved backend prefixes, missing-asset 404s, and GET/HEAD HTML negotiation.
  Serve immutable assets, no-cache HTML, and historical files only under `/assets`; never historical HTML.
- Use the included `Req` library for HTTP requests, not HTTPoison, Tesla, or `:httpc`.
- Router scopes already prefix route modules with their configured alias. Do not duplicate it.
- Do not use the removed `Phoenix.View` module.

## Elixir

- Define one module per file.
- Use `Enum.at/2` or pattern matching for list access, not index access syntax.
- Access struct fields directly or through the struct's API, not map access syntax.
- Bind the result of `if`, `case`, or `cond` when later code needs it.
  Rebinding inside a branch does not update the outer binding.
- Never call `String.to_atom/1` on user input.
- Name predicates with a trailing `?`; reserve `is_` names for guards.
- Use standard date and time modules. Do not add date/time dependencies without approval,
  except when date/time parsing requires one.
- Give named OTP supervisors and registries names in their child specifications.
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure.
  Use `timeout: :infinity` when tasks must be allowed to finish.

## Checks and tests

- A new public path on a hidden resource needs a player-view test. See "Product rules and
  documentation" in the root `AGENTS.md`. Register the path in the resource's surface coverage test.
- Read task help with `mix help <task>` before using unfamiliar Mix tasks.
- Run `mix precommit` after changes and fix failures.
- For focused failures, run `mix test <path>` or `mix test --failed`.
- Do not run `mix deps.clean --all` without a specific reason.
- Start test processes with `start_supervised!/1` so tests clean them up.
- Do not synchronize tests with `Process.sleep/1` or `Process.alive?/1`.
  Monitor termination and assert the `:DOWN` message, or use `:sys.get_state/1`
  to synchronize after earlier messages.
