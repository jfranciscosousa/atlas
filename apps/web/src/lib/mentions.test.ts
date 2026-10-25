import { test } from "node:test";
import assert from "node:assert/strict";

import { archivedEntries, buildEntries, describeMention } from "./mentions.ts";

const entries = buildEntries({
  characters: [
    { id: "c1", name: "Mira" },
    { id: "c2", name: null },
  ],
  sessions: [{ id: "s1", number: 3, title: null }],
  notes: [{ id: "n1", title: "Plot" }],
  entries: [
    { id: "e1", kind: "npc" as const, name: "Vex" },
    { id: "e2", kind: "location" as const, name: "Keep" },
  ],
  archivedNotes: [],
  archivedEntries: [],
});

test("an entry the reader can list shows its current name", () => {
  assert.deepEqual(describeMention(entries, [], "character", "c1"), {
    status: "found",
    label: "Mira",
  });
  assert.equal(
    describeMention(entries, [], "character", "c2").label,
    "Unnamed character"
  );
  assert.equal(
    describeMention(entries, [], "session", "s1").label,
    "Session 3"
  );
});

test("an unknown ID is a restricted entry, and an archived note is a deleted entry", () => {
  assert.equal(describeMention(entries, [], "note", "n9").status, "restricted");
  assert.equal(
    describeMention(entries, [{ kind: "note", id: "n9" }], "note", "n9").status,
    "deleted"
  );
  // The kind is part of the identity.
  assert.equal(
    describeMention(entries, [], "session", "c1").status,
    "restricted"
  );
});

test("a world entry shows its name, and its kind is part of its identity", () => {
  assert.deepEqual(describeMention(entries, [], "npc", "e1"), {
    status: "found",
    label: "Vex",
  });
  assert.equal(
    describeMention(entries, [], "location", "e1").status,
    "restricted"
  );
});

test("an entry the reader cannot list is restricted, and an archived one is deleted", () => {
  // A hidden entry is missing from a player's list.
  assert.equal(
    describeMention(entries, [], "npc", "e9").label,
    "Restricted entry"
  );
  assert.deepEqual(
    describeMention(entries, [{ kind: "faction", id: "e9" }], "faction", "e9"),
    { status: "deleted", label: "Deleted entry" }
  );
  assert.equal(
    describeMention(entries, [{ kind: "faction", id: "e9" }], "item", "e9")
      .status,
    "restricted"
  );
});

test("the archived notes and entries merge into one list", () => {
  assert.deepEqual(
    archivedEntries({
      characters: [],
      sessions: [],
      notes: [],
      entries: [],
      archivedNotes: [{ id: "n1" }],
      archivedEntries: [{ id: "e1", kind: "plot" }],
    }),
    [
      { kind: "note", id: "n1" },
      { kind: "plot", id: "e1" },
    ]
  );
});
