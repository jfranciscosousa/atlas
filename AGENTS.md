# Atlas

Atlas is one app: a collaborative, text-first RPG campaign manager.

## Repository

- `apps/api`: JSON-only Phoenix/Ash backend. Read `apps/api/AGENTS.md` before backend work.
- `apps/web`: TanStack Start SPA. All application pages belong here.
- `packages/api-client`: generated AshTypescript contracts. Run `pnpm run api:generate`
  from the root after changing exposed actions. Do not edit generated contracts by hand.
- Phoenix must not build or serve frontend assets or add application LiveViews.
- Preserve same-origin cookie authentication and CSRF protection.

## Package manager

- Use pnpm for all JavaScript dependencies, scripts, and tools. Use the version pinned in `package.json`.
- Use `pnpm exec` for installed tools and `pnpm dlx` for temporary tools. Do not use `npm`, `npm exec`, `npx`, Yarn, or Bun for these tasks.
- Keep `pnpm-lock.yaml` as the only JavaScript dependency lockfile.
- The Dockerfile may use npm only to install the pinned pnpm version globally.

## Checks

- Run `pnpm run precommit` from the root to check the frontend and backend.
- For backend-only changes, run `mix precommit` from `apps/api`; it does not require Node.
- Fix failures before reporting completion.
- Apply every new migration to the development database yourself. Do not ask. Use your worktree's
  database (`atlas_dev_<slug>`), not `atlas_dev`. One PostgreSQL server on port 5432 holds all of them.
- PostgreSQL runs as the systemd user service `atlas-postgres` (`mise run db:install` sets it up;
  `scripts/db-service status` checks it). Never start it with `pg_ctl` from your shell: it stops when
  your session ends. Never run `initdb`, or delete a data directory. If the server is down, run
  `mise run db:start`.
- `mix precommit` also runs `mix atlas.check_migrations`: every migration must apply to an empty
  database. A migration must not read a table that a later migration creates.
- A worktree has its own databases, `atlas_dev_<slug>` and `atlas_test_<slug>`. `scripts/worktree-setup`
  creates them and copies built dependencies from the main checkout. T3 Code runs it on worktree creation (`t3.json`).
  Run it yourself when `deps` is missing or a mix task fails on an unknown dependency. It prints one line
  per step and keeps the full output in a log file. `scripts/worktree-doctor` checks that the worktree is
  ready and prints the fix for each failure. Setup is safe: it calls
  `scripts/refresh-main`, which fast-forwards the main checkout only when it is clean and on `master`, and
  builds its dependencies. `scripts/refresh-main` is also safe to run alone. `--skip-refresh` skips it.
  `scripts/worktree-prune` lists the databases of deleted worktrees; `--force` drops them.
  `scripts/worktree-cleanup` does not run by itself. Run it by hand. It removes old, clean, fully merged
  worktrees and prunes; it only lists them unless you pass `--force`.
- Start the dev servers with `scripts/dev --detach`. They run as a systemd user service, so they survive
  the end of your shell. `scripts/dev status|logs|stop` act on this worktree only. Never use `pkill`,
  `killall` or `nohup` for the servers: `pkill -f` kills other worktrees' servers and your own shell.
  `pnpm run dev` runs them in the foreground. A worktree gets its own ports (web 3100-3499,
  API 4100-4499) from its directory name; the main checkout keeps 3000 and 4000. The script prints the URLs.
- Shell commands run with `LANG=C.UTF-8` (set in `mise.toml`). Do not export a locale yourself.
- To sign in during manual or browser checks, use `agent@example.com` / `dev-password-123`. Setup creates
  it in every worktree database. `mix atlas.dev_user [EMAIL]` creates or confirms any account without the
  confirmation email. It does not run in production.
- Use `scripts/browser` instead of `agent-browser`. It gives each worktree its own browser session, so
  agents in different worktrees do not share tabs or cookies. Never run `agent-browser close --all`.
  Before `open` and `auth login` on a local URL it checks the web server, the API and the database, and
  names the fault. Read that message before you retry a sign-in.
- To sign in, use an auth profile. Save it once, then log in with the URL of the dev server you started:
  `printf %s dev-password-123 | scripts/browser auth save atlas-dev --url http://localhost:3000/sign-in --username agent@example.com --password-stdin`
  `scripts/browser auth login atlas-dev --url <web URL from pnpm run dev>/sign-in`

## Git

- Do not create branches. Work in a worktree by default. A worktree has its own `fs/` branch;
  that is the only branch you create.
- Commit to `master` and push only when the user says to push to `master`.

## Product rules and documentation

Do not use Notion. Do not read it, write to it, or keep tasks, plans, or decisions in it. Do not
use GitHub Issues or any other tracker. The repository is the only source of truth.

- Read the code, the tests, and `GLOSSARY.md` before you build.
- A rule the user gives you in chat is a decision. Apply it in the code and the tests. Name it in
  the commit message.
- If the code or an earlier rule conflicts with what the user asks, stop and report the conflict.
  Do not override a decision silently.
- Treat a proposal or an open question as unresolved. Ask the user when it blocks the task.
- Do not add Markdown documentation or decision records unless the user asks. The exceptions are
  `AGENTS.md` and `GLOSSARY.md`.
- The app and MCP must match. Whatever a person sees in the app, the same person sees through
  MCP and the AI features, with the same names, labels, and access rules. When you change what
  one surface shows or hides, change the others in the same commit, and add a test that
  compares them. A difference is a bug, not a design choice.
- Every rich-text field behaves the same: one editor, one image behavior, one autosave path.
  Do not build a variant with fewer features.

## Domain docs

Atlas is one app with one glossary: `GLOSSARY.md` at the repository root. Read it before work.
Use its terms in code and tests. When a new term is resolved, add it there.
