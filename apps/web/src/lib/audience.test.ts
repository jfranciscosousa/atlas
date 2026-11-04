import { test } from "node:test";
import assert from "node:assert/strict";

import { ENTRY_KINDS } from "./entry-kinds.ts";
import { AUDIENCE_LABELS, FIXED_AUDIENCE, audienceOf } from "./audience.ts";

test("the secret sections are GM only, wherever they are", () => {
  assert.equal(audienceOf("session", "prep"), "gm_only");
  assert.equal(audienceOf("character", "secret_notes"), "gm_only");
  for (const kind of ENTRY_KINDS)
    assert.equal(audienceOf(kind, "secret_notes"), "gm_only");
});

test("a world entry description is GM only until the GM shows the entry", () => {
  for (const kind of ENTRY_KINDS) {
    assert.equal(
      audienceOf(kind, "description", { hidden: true, archivedAt: null }),
      "gm_only"
    );
    assert.equal(
      audienceOf(kind, "description", {
        hidden: false,
        archivedAt: "2026-01-01T00:00:00Z",
      }),
      "gm_only"
    );
    assert.equal(
      audienceOf(kind, "description", { hidden: false, archivedAt: null }),
      "everyone"
    );
  }
  // A missing state never promises more readers than the text has.
  assert.equal(audienceOf("npc", "description"), "gm_only");
});

test("a note body follows the visibility of the note", () => {
  for (const visibility of [
    "only_me",
    "me_and_gm",
    "character",
    "everyone",
  ] as const)
    assert.equal(audienceOf("note", "body", { visibility }), visibility);
  assert.equal(audienceOf("note", "body"), "only_me");
});

test("the text for members and for the owner alone", () => {
  assert.equal(audienceOf("campaign", "description"), "everyone");
  assert.equal(audienceOf("session", "log"), "everyone");
  assert.equal(audienceOf("player_log", "body"), "everyone");
  assert.equal(audienceOf("skill", "body"), "only_me");
});

test("every fixed audience has a label", () => {
  for (const audience of Object.values(FIXED_AUDIENCE))
    assert.ok(AUDIENCE_LABELS[audience]);
});
