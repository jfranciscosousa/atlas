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

## Git

- Do not create branches. Work in a worktree by default.
- Commit to `master` and push only when the user says to push to `master`.

## Documentation

Notion is the single source of truth for product documentation. All documentation lives in Notion,
not in this repository. The only exception is `GLOSSARY.md`. Do not add other Markdown
documentation or decision records here. Use the `ntn` CLI, not the Notion MCP.

- Before any feature, read the whole Atlas plan and every subpage that touches the feature. This
  includes the UX rules in Product & content (creation, lists, navigation, entry layout). Read the
  live pages with `ntn`. Never rely on a cached copy or on memory.
- Implement what Notion says. If the code needs to differ, stop and report the conflict.
- Save everything in Notion before you report completion: decisions, product and UX rules,
  what you built, deviations, gaps, and the task status.
- Update the page that owns the rule. Do not leave a new rule only in code or in chat.

### Keep Notion current while you work

- Update Notion as you go, not only at the end. Record a decision, a product or UX rule, or a
  deviation when it is made. Do not wait for the final report.
- At the start of a task, re-read the live pages and fix any drift between them and the code. Do
  this before you build.
- Create or update the Atlas task before you build. Set it to `In progress`. Set it to `Done` only
  after its acceptance criteria and `pnpm run precommit` pass.
- When a slice is built, update all of these:
  - The decision map: a "built" section, the decisions made while building, and what is not done.
  - Each plan page that owns an affected rule (Product & content, Access & collaboration, Ash
    domain model). Replace stale statements such as "not built" or "today only the GM can read".
  - "Where we paused" on the Atlas plan.
  - The task: result and deferred work.
  - `GLOSSARY.md`, when a new term is resolved.
- A user answer to a product question is a decision. Record it on the page that owns the rule in
  the same session.
- Verify each Notion write. Read the block back. Do not assume a silent `ntn` call succeeded.

`ntn` pitfalls:

- Quote paths that contain `?` in zsh, for example `"v1/blocks/<id>/children?page_size=100"`.
- Pass request bodies with `-d @file.json` and set the method with `-X PATCH` or `-X POST`.
- Close stdin when you call `ntn` from a script (`stdin=subprocess.DEVNULL`). It can hang
  otherwise.
- Do not use `pkill -f` with a pattern that appears in your own command line.

- [Atlas hub](https://app.notion.com/p/Atlas-3fd556c92b9f8180a81cd471d362e4cb)
- [Atlas plan](https://app.notion.com/p/Atlas-plan-3fd556c92b9f806487dfd0a7994f37b4):
  product rules, technical model, research, and open questions.
- [Atlas MVP decision map](https://app.notion.com/p/3fd556c92b9f810bb283fe7987745318):
  decision tickets and the build approach.
- [Atlas tasks](https://app.notion.com/p/407fd26b353540d29f291477adba0508):
  implementation work. Database ID `407fd26b-3535-40d2-9f29-1477adba0508`,
  data source ID `714c7cbb-62cb-4538-b8b2-9fb3e733cbdb`.

Read Atlas plan and the relevant subpages before planning or implementing work. Preserve agreed
product rules. Treat proposals and open questions as unresolved, and ask for a decision when they
block the task. Report conflicts with an existing decision. Do not override it silently.

## Agent skills

### Issue tracker

Track work in Notion, not GitHub Issues.

- Search existing tasks before creating one. Update the existing task when it covers the work.
- Each task describes the work, links its source planning pages, and states acceptance criteria.
- Read the data source schema before writing task properties: `Task name`, `Status`, `Assignee`, `Due`.
- Statuses: `Not started`, `In progress`, `Done`, `Archived`. Mark work done only after its
  acceptance criteria and required checks pass.
- Link tasks to the pull request when one exists.
- Keep planning content in the plan and implementation progress in tasks.
- If Notion access fails, report the failure. Do not switch trackers silently.
- Decision tickets are child pages of the decision map, not tasks. List them with
  `ntn api v1/blocks/<map-id>/children` and follow pagination. Each ticket records
  `Type: wayfinder:<type>`, `Status: Open` or `Resolved`, and `Claim: Unclaimed` or a name.
  Claim a ticket before work. Blockers are linked ticket names in its body. Record the answer in
  its `Resolution` section, mark it resolved, and add a short linked summary to the map's
  Decisions so far. Recommendations are not decisions; product choices need the user's answer.

### Domain docs

Atlas is one app with one glossary: `GLOSSARY.md` at the repository root. Read it before work.
Use its terms in code, tests, tasks, and proposals. When a new term is resolved, add it there.
Architecture decisions are decision tickets in Notion, not files in this repository.
