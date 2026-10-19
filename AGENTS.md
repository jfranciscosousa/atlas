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

## Git

- Do not create branches. Work in a worktree by default.
- Commit to `master` and push only when the user says to push to `master`.

## Documentation

All documentation lives in Notion, not in this repository. The only exception is `GLOSSARY.md`.
Do not add other Markdown documentation or decision records here. Use the `ntn` CLI,
not the Notion MCP.

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
