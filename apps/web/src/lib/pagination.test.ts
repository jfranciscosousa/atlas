import { test } from "node:test";
import assert from "node:assert/strict";

import { clampPage, pageCount, pageSlice, parsePage } from "./pagination.ts";

const items = Array.from({ length: 60 }, (_, index) => index + 1);

test("a list of 60 rows has three pages of 25, and an empty list has one", () => {
  assert.equal(pageCount(60), 3);
  assert.equal(pageCount(50), 2);
  assert.equal(pageCount(0), 1);
});

test("a page holds its own rows, and the last page holds the rest", () => {
  assert.deepEqual(pageSlice(items, 1), items.slice(0, 25));
  assert.deepEqual(pageSlice(items, 2), items.slice(25, 50));
  assert.deepEqual(pageSlice(items, 3), items.slice(50));
  assert.deepEqual(pageSlice([], 1), []);
});

test("a page that does not exist gives the nearest page that does", () => {
  assert.equal(clampPage(9, 60), 3);
  assert.equal(clampPage(0, 60), 1);
  assert.deepEqual(pageSlice(items, 9), items.slice(50));
});

test("the page in a URL is a whole number above 1, or nothing", () => {
  assert.equal(parsePage(2), 2);
  assert.equal(parsePage("3"), 3);
  for (const bad of [
    1,
    "1",
    0,
    -2,
    2.5,
    "2.5",
    "abc",
    "",
    undefined,
    null,
    NaN,
  ])
    assert.equal(parsePage(bad), undefined, String(bad));
});
