# Atlas

A monorepo with two independent applications:

```text
apps/
  api/                  Phoenix, Ash, authentication, PostgreSQL, and RPC
  web/                  TanStack Start SPA, Router, and Form
packages/
  api-client/           Generated AshTypescript client and types
```

The web app owns every application page, including password recovery and email
confirmation. Phoenix returns JSON and manages HTTP-only authentication cookies.
It does not build or serve the SPA. The only development UI is the local email
inbox.

## Development

Mise pins Node, pnpm 12.14.0, Elixir, Erlang, and PostgreSQL. Use pnpm for all
JavaScript dependencies and scripts.

Install the runtimes, start PostgreSQL, and install dependencies:

```bash
mise install
mise run db:start
pnpm install --frozen-lockfile
cd apps/api
mix setup
```

PostgreSQL must run on `localhost:5432`, with username `postgres` and password
`postgres`. Setup creates and migrates `atlas_dev`.

`mise run db:start` initializes the PostgreSQL cluster on first use and starts
it. `PGDATA` defaults to `~/.local/share/postgres`. An existing `PGDATA` takes
precedence. No global mise configuration is required. Data and logs stay in
that directory. The server listens only on localhost.

Stop it with `mise run db:stop`; this stops the shared server for all projects
and worktrees.

Port 5432 must be free unless this cluster already runs there. These tasks do
not stop an existing system PostgreSQL service.

Start both apps from the repository root:

```bash
pnpm run dev
```

Logs have `web` and `api` labels. Press Ctrl+C to stop both apps. If either
process exits, the other process stops too.

To start only one app, use `pnpm run web:dev` or `pnpm run api:dev`.

- App: **http://localhost:3000**
- API: **http://localhost:4000/api/session**
- Development email inbox: **http://localhost:4000/dev/mailbox**

Vite proxies `/api`, `/auth`, and `/rpc` to Phoenix. Set `API_URL` when starting
Vite to use a different backend address. API requests must use the app origin,
not port 4000 directly. This keeps cookies and CSRF protection same-origin.

Each app also runs directly: `mix phx.server` in `apps/api`, or `pnpm run dev`
in `apps/web`. Phoenix does not start Vite.

## Routes and authentication

Pathless layouts load session data in `beforeLoad`. The authenticated layout
exposes the current user through route context:

- `_guest`: `/`, `/register`, `/sign-in`, and `/reset`.
- `_authenticated`: `/dashboard`, with a non-null user in context.
- `_public`: `/password-reset/$token` and `/confirm_new_user/$token`.
  Email links work whether the visitor is signed in or signed out.

Guest pages redirect signed-in users to the dashboard. Protected pages redirect
anonymous users to login. API policies enforce authorization independently of
these frontend guards.

The API endpoints are:

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/session` | Current user and CSRF token |
| DELETE | `/api/session` | Revoke the current session and sign out |
| POST | `/auth/user/password/register` | Create an account |
| POST | `/auth/user/password/sign_in` | Sign in |
| POST | `/auth/user/password/reset_request` | Request a reset email |
| POST | `/auth/user/password/reset` | Reset a password with a token |
| POST | `/auth/user/confirm_new_user` | Confirm an email with a token |
| POST | `/rpc/run` | Run an exposed Ash action |
| POST | `/rpc/validate` | Validate an exposed Ash action |

Send `Accept: application/json` on API requests and an `x-csrf-token` header on
mutations. Auth endpoints accept a JSON `user` object. The frontend does not
receive or store authentication tokens.

Session responses update the query client's default query and mutation metadata
with the CSRF token. RPC functions read it from their execution context. Auth
requests use the same client defaults. Components and hooks do not receive CSRF
token props or arguments.

Reset requests return the same response for existing and unknown addresses.
Reset links are single-use. A password change revokes previous sessions.
After a reset, sign in with the new password.
Email confirmation requires a button click; opening the link does not confirm
the address.

Development emails link to `http://localhost:3000`. In production, set
`FRONTEND_URL` to the public HTTPS origin. It defaults to `https://$PHX_HOST`.
Configure a production Swoosh adapter and sender address before sending real
emails. The default adapter stores email locally.

## Generated API contract

After changing exposed Ash resources or actions:

```bash
pnpm run api:generate
```

This writes `packages/api-client/src/ash_rpc.ts` and `ash_types.ts`. Frontend
code can import `@atlas/api-client` or
`@atlas/api-client/types`. Do not edit generated files by hand.

Generation is explicit. Normal API builds do not require Node or a frontend
build. Normal web builds do not require Elixir or a running API.

### Todos

The dashboard uses the generated `listTodos`, `createTodo`, `updateTodo`, and
`destroyTodo` RPC functions. Users can add todos, mark them complete, reopen
them, and delete them. Titles must contain 1 to 200 characters after trimming.

`useTodosList`, `useTodosCreate`, `useTodosUpdate`, and `useTodosDelete` use
TanStack Query and call the generated RPC client directly. The dashboard loader
fills the query cache before rendering. Successful mutations refetch the list.
Cache keys include the user ID, and signing out clears the cache.
Todo types are inferred from the generated RPC client.

RPC endpoints require a signed-in session and a CSRF token. Ash policies limit
todo access to the owner. The server sets ownership from the session; clients
cannot assign or change it. Deleting an inaccessible or missing todo is a
successful no-op.

After pulling resource changes, apply database migrations from `apps/api`:

```bash
mix ash.migrate
```

## Checks

From the repository root:

```bash
pnpm run precommit
```

This checks web formatting, builds the static SPA, checks TypeScript and the
generated client, runs frontend tests, and runs the API's `mix precommit` alias.

Format the web app with `pnpm run web:format`. Check formatting without writing
with `pnpm run web:format:check` or `pnpm run web:format --check`.
Oxfmt sorts imports and Tailwind classes. It excludes the generated route tree.
Backend and generated API client files are outside its scope.

`pnpm install --frozen-lockfile` installs the Husky pre-commit hook. The hook formats staged web files
with lint-staged. VS Code recommends the Oxc extension and enables format-on-save
for web file types.

For API-only checks:

```bash
cd apps/api
mix precommit
```

## Production

Build each application separately:

```bash
pnpm install --frozen-lockfile
pnpm run web:build
cd apps/api
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix release
```

Deploy only `apps/web/dist/client/` to the static host. The temporary
`dist/server/` bundle prerenders the SPA shell during builds; do not run it
in production. No frontend Node server is required.

The API release needs `DATABASE_URL`, `SECRET_KEY_BASE`,
`TOKEN_SIGNING_SECRET`, `PHX_HOST`, and `PHX_SERVER=true`. Set
`FRONTEND_URL` if it differs from `https://$PHX_HOST`. Run database migrations
before serving traffic.

Use one public HTTPS origin:

```text
example.com/api/*    → Phoenix
example.com/auth/*   → Phoenix
example.com/rpc/*    → Phoenix
example.com/*        → Static SPA
```

Configure your hosting platform to implement this split and serve `index.html`
for frontend deep links. Production proxy configuration is not included.

Keep backend paths separate from the SPA fallback. Do not expose the API's
private port publicly. Production cookies require HTTPS. Separate origins
would need a deliberate CORS and cookie configuration; they are not enabled.
