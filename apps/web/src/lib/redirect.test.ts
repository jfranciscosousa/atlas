import { test } from "node:test";
import assert from "node:assert/strict";

import { safeRedirect } from "./redirect.ts";

test("safeRedirect keeps same-origin paths", () => {
  assert.equal(safeRedirect("/join/abc"), "/join/abc");
  assert.equal(safeRedirect("/campaigns?x=1#y"), "/campaigns?x=1#y");
});

test("safeRedirect drops other origins and non-strings", () => {
  for (const value of [
    "https://evil.example",
    "//evil.example",
    "/\\evil.example",
    "join/abc",
    "",
    undefined,
    42,
  ])
    assert.equal(safeRedirect(value), undefined);
});
