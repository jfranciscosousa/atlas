# Atlas

Atlas is one app: a collaborative, text-first RPG campaign manager.

## Repository

- `apps/api`: JSON-only Phoenix/Ash backend. Read `apps/api/AGENTS.md` before backend work.
- `apps/web`: TanStack Start SPA. All application pages belong here.
- `packages/api-client`: generated AshTypescript contracts. Run `pnpm run api:generate`
  from the root after changing exposed actions. Do not edit generated contracts by hand.
- Phoenix must not build or serve frontend assets or add application LiveViews.
- Preserve same-origin cookie authentication and CSRF protection.

## Checks

- Run `pnpm run precommit` from the root to check the frontend and backend.
- For backend-only changes, run `mix precommit` from `apps/api`; it does not require Node.
- Fix failures before reporting completion.
- Apply every new migration to the development database yourself. Do not ask. Find the database
  the running dev server uses first: its `PGPORT` is not always the default.
- A worktree has its own databases, `atlas_dev_<slug>` and `atlas_test_<slug>`. `scripts/worktree-setup`
  creates them and copies built dependencies from the main checkout. T3 Code runs it on worktree creation.
  `scripts/worktree-prune` lists the databases of deleted worktrees; `--force` drops them.
  `scripts/worktree-cleanup` runs when a T3 thread settles. It removes old, clean, fully merged worktrees and
  prunes; it only lists them unless you pass `--force`.
- Start the dev servers with `pnpm run dev`. A worktree gets its own ports (web 3100-3499, API 4100-4499)
  from its directory name; the main checkout keeps 3000 and 4000. The script prints the URLs.
- To sign in during manual or browser checks, use `agent@example.com` / `dev-password-123`. Setup creates
  it in every worktree database. `mix atlas.dev_user [EMAIL]` creates or confirms any account without the
  confirmation email. It does not run in production.
- Use `scripts/browser` instead of `agent-browser`. It gives each worktree its own browser session, so
  agents in different worktrees do not share tabs or cookies. Never run `agent-browser close --all`.
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
