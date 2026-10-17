import { test } from "node:test";
import assert from "node:assert/strict";
import { MutationObserver, QueryClient, type MutationFunctionContext } from "@tanstack/react-query";
import { createTodo } from "@lemonade-stand/api-client";
import { rpcOptions } from "./rpc.ts";
import { todosQueryOptions } from "../hooks/use-todos.ts";

test("todo queries infer RPC data, reuse fresh data, and separate users", async (t) => {
  const client = new QueryClient({ defaultOptions: { queries: { meta: { csrfToken: "owner-csrf" } } } });
  t.after(() => client.clear());
  const request = t.mock.method(globalThis, "fetch", async (_url: RequestInfo | URL, options?: RequestInit) => {
    const token = (options?.headers as Record<string, string>)["x-csrf-token"];
    return Response.json({ success: true, data: [{ id: token, title: "Buy lemons", completed: false }] });
  });

  const owner = todosQueryOptions("owner");
  const other = todosQueryOptions("other");
  const todos = await client.ensureQueryData(owner);
  assert.equal(todos[0].title, "Buy lemons");
  assert.equal(todos[0].completed, false);
  assert.deepEqual(await client.ensureQueryData(owner), todos);
  assert.equal(request.mock.calls.length, 1);
  client.setDefaultOptions({ queries: { meta: { csrfToken: "other-csrf" } } });
  assert.equal((await client.ensureQueryData(other))[0].id, "other-csrf");
  assert.equal(client.getQueryData(owner.queryKey)?.[0].id, "owner-csrf");
  assert.deepEqual(owner.queryKey, ["todos", "owner"]);
});

test("RPC failures become query errors without caching error responses", async (t) => {
  const client = new QueryClient({ defaultOptions: { queries: { meta: { csrfToken: "csrf" } } } });
  t.after(() => client.clear());
  const request = t.mock.method(globalThis, "fetch", async () =>
    Response.json({ success: false, errors: [{ message: "Title is required" }] }),
  );
  const options = todosQueryOptions("owner");
  await assert.rejects(client.fetchQuery(options), /Title is required/);
  assert.equal(request.mock.calls.length, 1);
  assert.equal(client.getQueryData(options.queryKey), undefined);

});

test("queries and mutations use updated CSRF defaults after a session change", async (t) => {
  const client = new QueryClient();
  t.after(() => client.clear());
  const tokens: string[] = [];
  t.mock.method(globalThis, "fetch", async (_url: RequestInfo | URL, options?: RequestInit) => {
    tokens.push((options?.headers as Record<string, string>)["x-csrf-token"]);
    const action = JSON.parse(options?.body as string).action;
    return Response.json({ success: true, data: action === "list_todos" ? [] : {} });
  });
  const options = todosQueryOptions("owner");
  const mutationOptions = {
    mutationFn: (title: string, { meta }: MutationFunctionContext) =>
      createTodo({ ...rpcOptions(meta), input: { title } }),
  };

  client.setDefaultOptions({
    queries: { meta: { csrfToken: "before-login" } },
    mutations: { meta: { csrfToken: "before-login" } },
  });
  const mutation = new MutationObserver(client, mutationOptions);
  await client.fetchQuery(options);
  await mutation.mutate("First todo");

  client.setDefaultOptions({
    queries: { meta: { csrfToken: "after-login" } },
    mutations: { meta: { csrfToken: "after-login" } },
  });
  mutation.setOptions(mutationOptions);
  await client.invalidateQueries({ queryKey: options.queryKey });
  await client.fetchQuery(options);
  await mutation.mutate("Second todo");
  assert.deepEqual(tokens, ["before-login", "before-login", "after-login", "after-login"]);
});

test("missing CSRF metadata stops RPC requests before sending them", async (t) => {
  const client = new QueryClient();
  t.after(() => client.clear());
  const request = t.mock.method(globalThis, "fetch", async () => Response.json({}));
  await assert.rejects(client.fetchQuery(todosQueryOptions("owner")), /session expired/);
  assert.throws(() => rpcOptions(undefined), /session expired/);
  assert.equal(request.mock.calls.length, 0);
});

test("cancelling queries aborts in-flight RPC reads before clearing session data", async (t) => {
  const client = new QueryClient({ defaultOptions: { queries: { meta: { csrfToken: "csrf" } } } });
  t.after(() => client.clear());
  let signal: AbortSignal | undefined;
  t.mock.method(globalThis, "fetch", async (_url: RequestInfo | URL, options?: RequestInit) => {
    signal = options?.signal ?? undefined;
    return new Promise<Response>((_resolve, reject) => {
      signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
    });
  });
  const pending = client.fetchQuery(todosQueryOptions("owner"));
  const rejection = assert.rejects(pending);
  await client.cancelQueries();
  await rejection;
  assert.equal(signal?.aborted, true);
  client.clear();
  assert.equal(client.getQueryCache().getAll().length, 0);
});
