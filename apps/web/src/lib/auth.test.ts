import { test } from "node:test";
import assert from "node:assert/strict";
import { QueryClient } from "@tanstack/react-query";

import { AuthError, sessionRequest } from "./auth.ts";

test("auth requests send cookies and CSRF headers, without exposing tokens", async t => {
  const session = {
    user: { id: "123", email: "user@example.com" },
    csrfToken: "next-csrf",
  };
  const queryClient = new QueryClient({
    defaultOptions: { mutations: { meta: { csrfToken: "csrf" } } },
  });
  t.after(() => queryClient.clear());
  const request = t.mock.method(
    globalThis,
    "fetch",
    async (_url: RequestInfo | URL, _options?: RequestInit) =>
      Response.json(session)
  );

  assert.deepEqual(
    await sessionRequest("/auth/user/password/sign_in", {
      method: "POST",
      queryClient,
      user: { email: "user@example.com", password: "password" },
    }),
    session
  );

  const [url, options] = request.mock.calls[0].arguments;
  assert.equal(url, "/auth/user/password/sign_in");
  assert.deepEqual(options, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      Accept: "application/json",
      "x-csrf-token": "csrf",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      user: { email: "user@example.com", password: "password" },
    }),
  });
});

test("session responses update CSRF metadata for queries and mutations", async t => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { staleTime: 10_000 },
      mutations: { retry: false },
    },
  });
  t.after(() => queryClient.clear());
  let revision = 0;
  const request = t.mock.method(globalThis, "fetch", async () =>
    Response.json({ user: null, csrfToken: `csrf-${++revision}` })
  );

  await sessionRequest("/api/session", { queryClient });
  await sessionRequest("/auth/user/password/sign_in", {
    method: "POST",
    queryClient,
  });
  await sessionRequest("/api/session", { method: "DELETE", queryClient });

  assert.deepEqual(
    request.mock.calls.map(
      ({ arguments: [, options] }) =>
        (options?.headers as Record<string, string>)["x-csrf-token"]
    ),
    [undefined, "csrf-1", "csrf-2"]
  );
  assert.equal(
    queryClient.getDefaultOptions().queries?.meta?.csrfToken,
    "csrf-3"
  );
  assert.equal(
    queryClient.getDefaultOptions().mutations?.meta?.csrfToken,
    "csrf-3"
  );
  assert.equal(queryClient.getDefaultOptions().queries?.staleTime, 10_000);
  assert.equal(queryClient.getDefaultOptions().mutations?.retry, false);
});

test("auth errors retain the safe server message", async t => {
  t.mock.method(globalThis, "fetch", async () =>
    Response.json({ error: "Incorrect email or password" }, { status: 401 })
  );
  await assert.rejects(
    sessionRequest("/auth/user/password/sign_in"),
    /Incorrect email or password/
  );
});

test("validation errors preserve field messages", async t => {
  const fields = {
    email:
      "An account with this email already exists. Sign in or reset your password.",
  };
  t.mock.method(globalThis, "fetch", async () =>
    Response.json(
      { error: "Check the highlighted fields.", fields },
      { status: 422 }
    )
  );

  await assert.rejects(
    sessionRequest("/auth/user/password/register"),
    error => {
      assert.ok(error instanceof AuthError);
      assert.deepEqual(error.fields, fields);
      return true;
    }
  );
});

test("an HTML error response produces a useful connection error", async t => {
  t.mock.method(
    globalThis,
    "fetch",
    async () =>
      new Response("<html>Unavailable</html>", {
        status: 503,
        headers: { "Content-Type": "text/html" },
      })
  );
  await assert.rejects(sessionRequest("/api/session"), /server is unavailable/);
});

test("HTML CSRF errors ask the user to reload", async t => {
  t.mock.method(
    globalThis,
    "fetch",
    async () => new Response("<html>Forbidden</html>", { status: 403 })
  );
  await assert.rejects(sessionRequest("/api/session"), /session expired/);
});

test("expired CSRF sessions ask the user to reload", async t => {
  t.mock.method(globalThis, "fetch", async () =>
    Response.json({ errors: { detail: "Forbidden" } }, { status: 403 })
  );
  await assert.rejects(sessionRequest("/api/session"), /session expired/);
});
