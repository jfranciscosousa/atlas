import { test } from "node:test";
import assert from "node:assert/strict";

import { buildEntries, describeMention } from "./mentions.ts";

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
  assert.deepEqual(describeMention(entries, "character", "c1"), {
    status: "found",
    label: "Mira",
  });
  assert.equal(
    describeMention(entries, "character", "c2").label,
    "Unnamed character"
  );
  assert.equal(describeMention(entries, "session", "s1").label, "Session 3");
});

test("an unknown ID is a restricted entry, and the kind is part of the identity", () => {
  assert.equal(describeMention(entries, "note", "n9").status, "restricted");
  assert.equal(describeMention(entries, "session", "c1").status, "restricted");
});

test("a world entry shows its name, and its kind is part of its identity", () => {
  assert.deepEqual(describeMention(entries, "npc", "e1"), {
    status: "found",
    label: "Vex",
  });
  assert.equal(describeMention(entries, "location", "e1").status, "restricted");
});

test("an entry the reader cannot list is restricted", () => {
  // A hidden entry is missing from a player's list.
  assert.equal(describeMention(entries, "npc", "e9").label, "Restricted entry");
});

test("an archived note or entry keeps its name and is marked archived", () => {
  const withArchived = buildEntries({
    characters: [],
    sessions: [],
    notes: [],
    entries: [],
    archivedNotes: [{ id: "n1", title: "Old plan" }],
    archivedEntries: [{ id: "e1", kind: "plot" as const, name: "Old plot" }],
  });
  assert.deepEqual(withArchived, [
    { kind: "note", id: "n1", label: "Old plan", archived: true },
    { kind: "plot", id: "e1", label: "Old plot", archived: true },
  ]);
  assert.deepEqual(describeMention(withArchived, "plot", "e1"), {
    status: "found",
    label: "Old plot",
  });
});
