import { test } from "node:test";
import assert from "node:assert/strict";

import {
  authRedirect,
  consumeAuthRedirect,
  rememberAuthRedirect,
  safeRedirect,
} from "./redirect.ts";

test("safeRedirect keeps same-origin paths", () => {
  assert.equal(safeRedirect("/join/abc"), "/join/abc");
  assert.equal(safeRedirect("/campaigns?x=1#y"), "/campaigns?x=1#y");
});

test("safeRedirect drops other origins and non-strings", () => {
  for (const value of [
    "https://evil.example",
    "//evil.example",
    "/\\evil.example",
    "/\n/evil.example",
    "/\t/evil.example",
    "/campaigns\\..\\evil.example",
    "join/abc",
    "",
    undefined,
    42,
  ])
    assert.equal(safeRedirect(value), undefined);
});

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    },
    removeItem: (key: string) => {
      values.delete(key);
    },
  };
}

test("signup retains the claim destination for confirmation in another tab", () => {
  const storage = memoryStorage();
  rememberAuthRedirect("/claim/character-token", storage, 100);
  assert.equal(authRedirect(undefined, storage, 200), "/claim/character-token");
  // Confirmation has no redirect parameter and shares only localStorage.
  assert.equal(
    consumeAuthRedirect(undefined, storage, 300),
    "/claim/character-token"
  );
  assert.equal(authRedirect(undefined, storage, 400), "/campaigns");
});

test("login, signup, and password reset preserve paths, queries, and fragments", () => {
  const storage = memoryStorage();
  const path = "/join/invitation?source=friend#character";
  rememberAuthRedirect(path, storage, 100);
  assert.equal(authRedirect(path, storage, 200), path);
  assert.equal(authRedirect(undefined, storage, 300), path);
  assert.equal(consumeAuthRedirect(path, storage, 400), path);
  assert.equal(authRedirect(undefined, storage, 500), "/campaigns");
});

test("an explicit destination overrides an earlier authentication flow", () => {
  const storage = memoryStorage();
  rememberAuthRedirect("/claim/old", storage, 100);
  rememberAuthRedirect("/claim/new", storage, 200);
  assert.equal(
    consumeAuthRedirect("/join/current", storage, 300),
    "/join/current"
  );
  assert.equal(authRedirect(undefined, storage, 400), "/campaigns");
});

test("saved destinations expire and external redirects are never saved", () => {
  const storage = memoryStorage();
  rememberAuthRedirect("https://evil.example", storage, 100);
  assert.equal(authRedirect(undefined, storage, 200), "/campaigns");
  rememberAuthRedirect("/claim/expired", storage, 100);
  assert.equal(
    authRedirect(undefined, storage, 100 + 60 * 60 * 1000),
    "/campaigns"
  );
});

test("malformed and unavailable storage do not block authentication", () => {
  const malformed = { ...memoryStorage(), getItem: () => "not JSON" };
  assert.equal(authRedirect(undefined, malformed), "/campaigns");
  const unavailable = {
    getItem: (): string | null => {
      throw new Error("blocked");
    },
    setItem: () => {
      throw new Error("blocked");
    },
    removeItem: () => {
      throw new Error("blocked");
    },
  };
  assert.doesNotThrow(() => rememberAuthRedirect("/claim/token", unavailable));
  assert.equal(authRedirect(undefined, unavailable), "/campaigns");
  assert.equal(
    consumeAuthRedirect("/claim/token", unavailable),
    "/claim/token"
  );
});
