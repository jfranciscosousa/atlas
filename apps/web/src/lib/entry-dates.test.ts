import { test } from "node:test";
import assert from "node:assert/strict";

import { formatExactly, formatWhen } from "./entry-dates.ts";

const NOW = Date.parse("2026-11-05T12:00:00Z");
const ago = (ms: number) => new Date(NOW - ms).toISOString();
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

test("a recent moment reads as how long ago it was", () => {
  assert.equal(formatWhen(ago(10_000), NOW, "en"), "just now");
  assert.equal(formatWhen(ago(5 * MINUTE), NOW, "en"), "5 minutes ago");
  assert.equal(formatWhen(ago(3 * HOUR), NOW, "en"), "3 hours ago");
  assert.equal(formatWhen(ago(DAY), NOW, "en"), "yesterday");
  assert.equal(formatWhen(ago(3 * DAY), NOW, "en"), "3 days ago");
});

test("a clock a little ahead of the server never shows the future", () => {
  assert.equal(formatWhen(ago(-5 * MINUTE), NOW, "en"), "just now");
});

test("an older moment is a calendar date, with the year only when it is not this year", () => {
  assert.equal(formatWhen(ago(40 * DAY), NOW, "en"), "Sep 26");
  assert.equal(formatWhen(ago(400 * DAY), NOW, "en"), "Oct 1, 2025");
});

test("the exact moment has a date and a time", () => {
  assert.match(formatExactly("2026-11-05T12:30:00Z", "en"), /2026/);
});
