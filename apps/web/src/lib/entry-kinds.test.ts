import { test } from "node:test";
import assert from "node:assert/strict";

import {
  ENTRY_KIND_LABELS,
  ENTRY_KINDS,
  endKindLabel,
  endPath,
  isEntryKind,
  statusLabel,
} from "./entry-kinds.ts";
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

test("an end opens its own page, and a preview opens the player's page", () => {
  assert.equal(endPath("c1", "character", "h1"), "/campaigns/c1/characters/h1");
  assert.equal(endPath("c1", "npc", "e1"), "/campaigns/c1/entries/e1");
  assert.equal(
    endPath("c1", "faction", "e1", true),
    "/campaigns/c1/preview/entries/e1"
  );
  // A character has no player's preview page.
  assert.equal(
    endPath("c1", "character", "h1", true),
    "/campaigns/c1/characters/h1"
  );
});

test("kinds and statuses read as words", () => {
  assert.equal(endKindLabel("character"), "Character");
  assert.equal(endKindLabel("npc"), "NPC");
  assert.equal(statusLabel("missing"), "Missing");
});
