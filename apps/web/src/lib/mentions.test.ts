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
  archivedNotes: [],
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
    describeMention(entries, [{ id: "n9" }], "note", "n9").status,
    "deleted"
  );
  // The kind is part of the identity.
  assert.equal(
    describeMention(entries, [], "session", "c1").status,
    "restricted"
  );
});
