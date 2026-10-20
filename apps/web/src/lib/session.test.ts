import { test } from "node:test";
import assert from "node:assert/strict";

import { formatPlayedOn, sessionLabel } from "./session.ts";

test("a session label shows the number and the title when there is one", () => {
  assert.equal(sessionLabel({ number: 3, title: null }), "Session 3");
  assert.equal(
    sessionLabel({ number: 3, title: "The Sunken Keep" }),
    "Session 3: The Sunken Keep"
  );
});

test("a played date keeps its day in every time zone", () => {
  assert.equal(formatPlayedOn(null), null);
  const text = formatPlayedOn("2026-10-20")!;
  assert.match(text, /20/);
});
