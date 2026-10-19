import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createCampaign,
  listCampaigns,
  validateCreateCampaign,
} from "@atlas/api-client";

import { rpcOptions } from "./rpc.ts";

test("generated campaign actions send same-origin cookies, CSRF, and typed RPC payloads", async t => {
  const request = t.mock.method(
    globalThis,
    "fetch",
    async (_url: RequestInfo | URL, _options?: RequestInit) =>
      Response.json({ success: true, data: {} })
  );
  const config = rpcOptions({ csrfToken: "session-csrf" });

  await listCampaigns({ ...config, fields: ["id", "name"] });
  await createCampaign({ ...config, input: { name: "Ember" }, fields: ["id"] });
  await validateCreateCampaign({ ...config, input: { name: "" } });

  const payloads = [
    { action: "list_campaigns", fields: ["id", "name"] },
    { action: "create_campaign", input: { name: "Ember" }, fields: ["id"] },
    { action: "create_campaign", input: { name: "" } },
  ];

  request.mock.calls.forEach(({ arguments: [url, options] }, index) => {
    assert.equal(url, index === 2 ? "/rpc/validate" : "/rpc/run");
    assert.equal(options?.method, "POST");
    assert.equal(options?.credentials, "same-origin");
    assert.equal(options?.cache, "no-store");
    assert.deepEqual(options?.headers, {
      "Content-Type": "application/json",
      "x-csrf-token": "session-csrf",
    });
    assert.deepEqual(JSON.parse(options?.body as string), payloads[index]);
  });
});

test("generated RPC calls preserve validation failures and handle expired sessions", async t => {
  const failure = {
    success: false,
    errors: [{ message: "Name is required", fields: ["name"] }],
  };
  t.mock.method(globalThis, "fetch", async () => Response.json(failure));
  assert.deepEqual(
    await createCampaign({
      ...rpcOptions({ csrfToken: "csrf" }),
      input: { name: "" },
    }),
    failure
  );

  t.mock.method(
    globalThis,
    "fetch",
    async () => new Response(null, { status: 401 })
  );
  const result = await listCampaigns({
    ...rpcOptions({ csrfToken: "csrf" }),
    fields: ["id"],
  });
  assert.equal(result.success, false);
  if (!result.success) assert.equal(result.errors[0].type, "network_error");
});
