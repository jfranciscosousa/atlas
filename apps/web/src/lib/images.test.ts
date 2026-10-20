import { test } from "node:test";
import assert from "node:assert/strict";

import { createImageResolver, uploadImage } from "./images.ts";

const campaignId = "5f1f6f2e-0000-4000-8000-000000000000";

test("an upload posts multipart with the CSRF token and returns a stable reference", async t => {
  const request = t.mock.fn(
    async (_url: RequestInfo | URL, _init?: RequestInit) =>
      Response.json({ id: "img-1" }, { status: 201 })
  );
  const file = new File(["x"], "a.png", { type: "image/png" });

  const reference = await uploadImage({
    parent: { kind: "campaign", id: campaignId },
    section: "description",
    file,
    csrfToken: "csrf",
    fetchImpl: request as unknown as typeof fetch,
  });

  assert.equal(reference, "atlas-image:img-1");
  const [url, init] = request.mock.calls[0]!.arguments;
  assert.equal(url, `/api/campaigns/${campaignId}/sections/description/images`);
  assert.equal(init?.method, "POST");
  assert.equal(init?.credentials, "same-origin");
  assert.equal(
    (init?.headers as Record<string, string>)["x-csrf-token"],
    "csrf"
  );
  assert.ok(init?.body instanceof FormData);
});

test("an upload into a note or a session goes to that parent's route", async t => {
  const request = t.mock.fn(
    async (_url: RequestInfo | URL, _init?: RequestInit) =>
      Response.json({ id: "img-2" }, { status: 201 })
  );
  const file = new File(["x"], "a.png", { type: "image/png" });

  for (const [kind, path, section] of [
    ["note", "notes", "body"],
    ["session", "sessions", "prep"],
  ] as const) {
    await uploadImage({
      parent: { kind, id: "abc" },
      section,
      file,
      csrfToken: "csrf",
      fetchImpl: request as unknown as typeof fetch,
    });
    const [url] = request.mock.calls.at(-1)!.arguments;
    assert.equal(url, `/api/${path}/abc/sections/${section}/images`);
  }
});

test("an upload shows the server message when it fails", async () => {
  const fetchImpl = (async () =>
    Response.json(
      { error: "Use a JPEG, PNG, WebP, GIF, SVG or AVIF image." },
      { status: 415 }
    )) as unknown as typeof fetch;

  await assert.rejects(
    uploadImage({
      parent: { kind: "campaign", id: campaignId },
      section: "description",
      file: new File(["x"], "a.pdf"),
      csrfToken: "csrf",
      fetchImpl,
    }),
    /Use a JPEG/
  );
});

test("an upload over 25 MB is refused before any request", async () => {
  const fetchImpl = (async () => {
    throw new Error("must not be called");
  }) as unknown as typeof fetch;
  const big = new File([new Uint8Array(25 * 1024 * 1024 + 1)], "big.png");

  await assert.rejects(
    uploadImage({
      parent: { kind: "campaign", id: campaignId },
      section: "description",
      file: big,
      csrfToken: "csrf",
      fetchImpl,
    }),
    /25 MB/
  );
});

test("the resolver caches a signed URL, refreshes it after the TTL, and drops failures", async () => {
  let time = 0;
  let calls = 0;
  let fail = false;
  const resolve = createImageResolver({
    ttlMs: 1000,
    now: () => time,
    fetchUrl: async id => {
      calls++;
      if (fail) throw new Error("denied");
      return `/api/images/${id}-${calls}`;
    },
  });

  assert.equal(await resolve("atlas-image:a"), "/api/images/a-1");
  assert.equal(await resolve("atlas-image:a"), "/api/images/a-1");
  time = 1001;
  assert.equal(await resolve("atlas-image:a"), "/api/images/a-2");

  assert.equal(
    await resolve("https://example.com/x.png"),
    "https://example.com/x.png"
  );

  fail = true;
  await assert.rejects(resolve("atlas-image:b"), /denied/);
  fail = false;
  assert.equal(await resolve("atlas-image:b"), "/api/images/b-4");
});
