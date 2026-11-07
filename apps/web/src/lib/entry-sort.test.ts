import { test } from "node:test";
import assert from "node:assert/strict";

import {
  DEFAULT_ENTRY_SORT,
  ENTRY_SORT_LABELS,
  ENTRY_SORTS,
  entrySortOf,
  isEntrySort,
} from "./entry-sort.ts";

test("every sort has a label, and latest session mention is the default", () => {
  assert.equal(DEFAULT_ENTRY_SORT, "last_mentioned");
  assert.equal(ENTRY_SORTS[0], DEFAULT_ENTRY_SORT);
  for (const sort of ENTRY_SORTS) assert.ok(ENTRY_SORT_LABELS[sort]);
});

test("an unknown sort in a URL gives the default", () => {
  assert.equal(entrySortOf("last_created"), "last_created");
  assert.equal(entrySortOf("name"), "name");
  assert.equal(entrySortOf("bogus"), "last_mentioned");
  assert.equal(entrySortOf(1), "last_mentioned");
  assert.equal(entrySortOf(undefined), "last_mentioned");
});

test("only a known sort is a sort", () => {
  assert.ok(isEntrySort("last_mentioned"));
  assert.ok(!isEntrySort("colour"));
  assert.ok(!isEntrySort(undefined));
  assert.ok(!isEntrySort(["name"]));
});
