import { test } from "node:test";
import assert from "node:assert/strict";

import {
  groupHits,
  highlight,
  hitPath,
  queryTerms,
  type SearchHit,
} from "./search.ts";

const hit = (kind: SearchHit["kind"], id: string): SearchHit => ({
  kind,
  id,
  title: id,
  campaign_id: "c1",
  campaign_name: "Keep",
  session_id: null,
  sections: [],
});

test("every kind opens its own page", () => {
  const base = { campaign_id: "c1", session_id: "s1" };
  assert.equal(
    hitPath({ ...base, kind: "campaign", id: "c1" }),
    "/campaigns/c1"
  );
  assert.equal(
    hitPath({ ...base, kind: "session", id: "s1" }),
    "/campaigns/c1/sessions/s1"
  );
  assert.equal(
    hitPath({ ...base, kind: "character", id: "h1" }),
    "/campaigns/c1/characters/h1"
  );
  assert.equal(
    hitPath({ ...base, kind: "note", id: "n1" }),
    "/campaigns/c1/notes/n1"
  );
});

test("a player log opens the page of its session", () => {
  assert.equal(
    hitPath({
      kind: "player_log",
      id: "log1",
      campaign_id: "c1",
      session_id: "s9",
    }),
    "/campaigns/c1/sessions/s9"
  );
});

test("groups follow the fixed kind order and keep the rank inside a group", () => {
  const groups = groupHits([
    hit("note", "n1"),
    hit("session", "s1"),
    hit("note", "n2"),
    hit("campaign", "c1"),
  ]);
  assert.deepEqual(
    groups.map(({ kind, hits }) => [kind, hits.map(h => h.id)]),
    [
      ["campaign", ["c1"]],
      ["session", ["s1"]],
      ["note", ["n1", "n2"]],
    ]
  );
});

test("query terms ignore case, accents and punctuation", () => {
  assert.deepEqual(queryTerms("  Dragón, dragón! Keep "), ["dragon", "keep"]);
  assert.deepEqual(queryTerms("?!"), []);
});

test("highlight marks whole words that contain a term", () => {
  assert.deepEqual(
    highlight("The Dragons' hoard, in Dragón-keep", ["dragon"]),
    [
      { text: "The ", match: false },
      { text: "Dragons", match: true },
      { text: "' hoard, in ", match: false },
      { text: "Dragón", match: true },
      { text: "-keep", match: false },
    ]
  );
});

test("highlight returns the text whole when no word matches", () => {
  assert.deepEqual(highlight("A torch", ["dragon"]), [
    { text: "A torch", match: false },
  ]);
  assert.deepEqual(highlight("", ["dragon"]), []);
});
