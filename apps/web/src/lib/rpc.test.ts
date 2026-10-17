import { test } from "node:test";
import assert from "node:assert/strict";
import { createTodo, destroyTodo, listTodos, updateTodo, validateCreateTodo } from "@lemonade-stand/api-client";
import { rpcOptions } from "./rpc.ts";

test("generated todo actions send same-origin cookies, CSRF, and typed RPC payloads", async (t) => {
  const request = t.mock.method(globalThis, "fetch", async (_url: RequestInfo | URL, _options?: RequestInit) =>
    Response.json({ success: true, data: {} }),
  );
  const config = rpcOptions({ csrfToken: "session-csrf" });
  const id = "be028f1e-24f8-4a57-9c2b-24815e96de42";

  await listTodos({ ...config, fields: ["id", "title", "completed"] });
  await createTodo({ ...config, input: { title: "Buy lemons" }, fields: ["id"] });
  await updateTodo({ ...config, identity: id, input: { completed: true }, fields: ["id", "completed"] });
  await destroyTodo({ ...config, identity: id });
  await validateCreateTodo({ ...config, input: { title: "" } });

  const payloads = [
    { action: "list_todos", fields: ["id", "title", "completed"] },
    { action: "create_todo", input: { title: "Buy lemons" }, fields: ["id"] },
    { action: "update_todo", identity: id, input: { completed: true }, fields: ["id", "completed"] },
    { action: "destroy_todo", identity: id },
    { action: "create_todo", input: { title: "" } },
  ];

  request.mock.calls.forEach(({ arguments: [url, options] }, index) => {
    assert.equal(url, index === 4 ? "/rpc/validate" : "/rpc/run");
    assert.equal(options?.method, "POST");
    assert.equal(options?.credentials, "same-origin");
    assert.equal(options?.cache, "no-store");
    assert.deepEqual(options?.headers, { "Content-Type": "application/json", "x-csrf-token": "session-csrf" });
    assert.deepEqual(JSON.parse(options?.body as string), payloads[index]);
  });
});

test("generated RPC calls preserve validation failures and handle expired sessions", async (t) => {
  const failure = { success: false, errors: [{ message: "Title is required", fields: ["title"] }] };
  t.mock.method(globalThis, "fetch", async () => Response.json(failure));
  assert.deepEqual(await createTodo({ ...rpcOptions({ csrfToken: "csrf" }), input: { title: "" } }), failure);

  t.mock.method(globalThis, "fetch", async () => new Response(null, { status: 401 }));
  const result = await listTodos({ ...rpcOptions({ csrfToken: "csrf" }), fields: ["id"] });
  assert.equal(result.success, false);
  if (!result.success) assert.equal(result.errors[0].type, "network_error");
});
