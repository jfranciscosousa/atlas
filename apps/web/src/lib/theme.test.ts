import { test } from "node:test";
import assert from "node:assert/strict";

import {
  THEME_INIT_SCRIPT,
  THEME_STORAGE_KEY,
  parseTheme,
  resolveTheme,
} from "./theme.ts";

test("an unknown stored theme falls back to the system preference", () => {
  assert.equal(parseTheme(null), "system");
  assert.equal(parseTheme("sepia"), "system");
  assert.equal(parseTheme("dark"), "dark");
  assert.equal(parseTheme("light"), "light");
});

test("the system theme follows the operating system", () => {
  assert.equal(resolveTheme("system", true), "dark");
  assert.equal(resolveTheme("system", false), "light");
});

test("an explicit theme ignores the operating system", () => {
  assert.equal(resolveTheme("light", true), "light");
  assert.equal(resolveTheme("dark", false), "dark");
});

// The init script is a string, so run it against stubs to prove it matches `resolveTheme`.
function initClass(stored: string | null, prefersDark: boolean) {
  const classes = new Set<string>();
  const documentElement = {
    classList: {
      toggle: (name: string, on: boolean) =>
        on ? classes.add(name) : classes.delete(name),
    },
    style: {} as { colorScheme?: string },
  };
  new Function("localStorage", "matchMedia", "document", THEME_INIT_SCRIPT)(
    {
      getItem: (key: string) => (key === THEME_STORAGE_KEY ? stored : null),
    },
    () => ({ matches: prefersDark }),
    { documentElement }
  );
  return {
    dark: classes.has("dark"),
    scheme: documentElement.style.colorScheme,
  };
}

test("the head script applies the same theme as the app", () => {
  for (const stored of [null, "system", "light", "dark", "junk"]) {
    for (const prefersDark of [true, false]) {
      const expected = resolveTheme(parseTheme(stored), prefersDark);
      const actual = initClass(stored, prefersDark);
      assert.equal(
        actual.dark,
        expected === "dark",
        `${stored} ${prefersDark}`
      );
      assert.equal(actual.scheme, expected);
    }
  }
});
