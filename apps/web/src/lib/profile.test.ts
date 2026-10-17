import { test } from "node:test";
import assert from "node:assert/strict";
import { MutationObserver, QueryClient } from "@tanstack/react-query";
import { updateProfile } from "@atlas/api-client";

import { rpcOptions } from "./rpc.ts";
import { readAvatar } from "./avatar.ts";
import { profileQueryOptions } from "../hooks/use-profile.ts";

test("profile queries use cookie authentication, CSRF, and separate user caches", async t => {
  const client = new QueryClient({
    defaultOptions: { queries: { meta: { csrfToken: "profile-csrf" } } },
  });
  t.after(() => client.clear());
  const profile = {
    id: "owner",
    email: "owner@example.com",
    displayName: "Jane",
    avatar: null,
  };
  const request = t.mock.method(
    globalThis,
    "fetch",
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      assert.equal(options?.credentials, "same-origin");
      assert.equal(options?.cache, "no-store");
      assert.equal(
        (options?.headers as Record<string, string>)["x-csrf-token"],
        "profile-csrf"
      );
      assert.equal(JSON.parse(options?.body as string).action, "get_profile");
      return Response.json({ success: true, data: profile });
    }
  );

  const owner = profileQueryOptions("owner");
  assert.deepEqual(await client.ensureQueryData(owner), profile);
  assert.deepEqual(await client.ensureQueryData(owner), profile);
  assert.equal(request.mock.calls.length, 1);
  assert.equal(
    client.getQueryData(profileQueryOptions("other").queryKey),
    undefined
  );
});

test("profile query errors are not stored as profile data", async t => {
  const client = new QueryClient({
    defaultOptions: { queries: { meta: { csrfToken: "csrf" } } },
  });
  t.after(() => client.clear());
  t.mock.method(globalThis, "fetch", async () =>
    Response.json({
      success: false,
      errors: [{ message: "Profile unavailable" }],
    })
  );
  const options = profileQueryOptions("owner");
  await assert.rejects(client.fetchQuery(options), /Profile unavailable/);
  assert.equal(client.getQueryData(options.queryKey), undefined);
});

test("profile mutations send the owner ID and preserve base64 and removal values", async t => {
  const client = new QueryClient({
    defaultOptions: { mutations: { meta: { csrfToken: "csrf" } } },
  });
  t.after(() => client.clear());
  const inputs = [
    { displayName: "Jane", avatar: "data:image/png;base64,iVBORw0KGgo=" },
    { displayName: "Jane", avatar: null },
  ];
  const received: unknown[] = [];
  t.mock.method(
    globalThis,
    "fetch",
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      const body = JSON.parse(options?.body as string);
      assert.equal(body.action, "update_profile");
      assert.equal(body.identity, "owner");
      assert.equal(
        (options?.headers as Record<string, string>)["x-csrf-token"],
        "csrf"
      );
      received.push(body.input);
      return Response.json({ success: true, data: {} });
    }
  );
  const mutation = new MutationObserver(client, {
    mutationFn: (input: (typeof inputs)[number], { meta }) =>
      updateProfile({ ...rpcOptions(meta), identity: "owner", input }),
  });
  for (const input of inputs) await mutation.mutate(input);
  assert.deepEqual(received, inputs);
});

test("avatar uploads reject unsupported types and oversized files before reading", async () => {
  await assert.rejects(
    readAvatar(new File(["<svg/>"], "photo.svg", { type: "image/svg+xml" })),
    /PNG, JPEG, or WebP/
  );
  await assert.rejects(
    readAvatar(
      new File([new Uint8Array(512 * 1024 + 1)], "photo.png", {
        type: "image/png",
      })
    ),
    /512 KB/
  );
});

test("avatar uploads resolve data URLs and report file read errors", async t => {
  const dataUrl = "data:image/png;base64,iVBORw0KGgo=";
  let fail = false;
  class TestFileReader {
    result = dataUrl;
    onload?: () => void;
    onerror?: () => void;
    readAsDataURL() {
      if (fail) this.onerror?.();
      else this.onload?.();
    }
  }
  const original = Object.getOwnPropertyDescriptor(globalThis, "FileReader");
  Object.defineProperty(globalThis, "FileReader", {
    value: TestFileReader,
    configurable: true,
  });
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "FileReader", original);
    else Reflect.deleteProperty(globalThis, "FileReader");
  });
  const file = new File(["image"], "photo.png", { type: "image/png" });
  assert.equal(await readAvatar(file), dataUrl);
  fail = true;
  await assert.rejects(readAvatar(file), /Could not read the image/);
});
