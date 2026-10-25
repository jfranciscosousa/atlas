import { test } from "node:test";
import assert from "node:assert/strict";

import { ENTRY_KIND_LABELS, ENTRY_KINDS, isEntryKind } from "./entry-kinds.ts";
import { MENTION_KINDS } from "./blocknote-schema.ts";

test("every kind of world entry has a name and can be mentioned", () => {
  assert.deepEqual(ENTRY_KINDS, [
    "npc",
    "location",
    "faction",
    "item",
    "creature",
    "plot",
  ]);
  for (const kind of ENTRY_KINDS) {
    assert.ok(ENTRY_KIND_LABELS[kind].label);
    assert.ok(MENTION_KINDS.includes(kind));
  }
  assert.ok(isEntryKind("npc"));
  assert.ok(!isEntryKind("note"));
});
