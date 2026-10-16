# Lemonade Stand

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

Install the runtimes, start PostgreSQL, and install dependencies:

```bash
mise install
npm ci
cd apps/api
mix setup
```

PostgreSQL must run on `localhost:5432`, with username `postgres` and password
`postgres`. Setup creates and migrates `lemonade_stand_dev`.

Run these commands from the repository root in separate terminals:

```bash
npm run dev:api
npm run dev
```

- App: **http://localhost:3000**
- API: **http://localhost:4000/api/session**
- Development email inbox: **http://localhost:4000/dev/mailbox**

Vite proxies `/api`, `/auth`, and `/rpc` to Phoenix. Set `API_URL` when starting
Vite to use a different backend address. API requests must use the app origin,
not port 4000 directly. This keeps cookies and CSRF protection same-origin.

Each app also runs directly: `mix phx.server` in `apps/api`, or `npm run dev`
in `apps/web`. Phoenix does not start Vite.

## Routes and authentication

Pathless layouts load session data in `beforeLoad` and expose it through route
context:

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
npm run generate:api
```

This writes `packages/api-client/src/ash_rpc.ts` and `ash_types.ts`. Frontend
code can import `@lemonade-stand/api-client` or
`@lemonade-stand/api-client/types`. Do not edit generated files by hand.

Generation is explicit. Normal API builds do not require Node or a frontend
build. Normal web builds do not require Elixir or a running API.

## Checks

From the repository root:

```bash
npm run precommit
```

This builds the static SPA, checks TypeScript and the generated client, runs
frontend tests, and runs the API's `mix precommit` alias.

For API-only checks:

```bash
cd apps/api
mix precommit
```

## Production

Build each application separately:

```bash
npm ci
npm run build
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
