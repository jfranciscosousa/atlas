import { test } from "node:test";
import assert from "node:assert/strict";

import { highlight, hitPath, queryTerms } from "./search.ts";

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

test("query terms ignore case, accents and punctuation", () => {
  assert.deepEqual(queryTerms("  Dragón, dragón! Keep "), ["dragon", "keep"]);
  assert.deepEqual(queryTerms("?!"), []);
});

test("punctuation inside a query word joins it, as the API does", () => {
  assert.deepEqual(queryTerms("M.A.77"), ["ma77"]);
  assert.deepEqual(queryTerms("MA77 m.a.77 In-world"), ["ma77", "inworld"]);
});

test("highlight marks whole chunks that contain a term", () => {
  assert.deepEqual(
    highlight("The Dragons' hoard, in Dragón-keep", ["dragon"]),
    [
      { text: "The ", match: false },
      { text: "Dragons", match: true },
      { text: "' hoard, in ", match: false },
      { text: "Dragón-keep", match: true },
    ]
  );
});

test("highlight finds a joined query word in a punctuated chunk", () => {
  assert.deepEqual(highlight("Meet at M.A.77 or MA77.", ["ma77"]), [
    { text: "Meet at ", match: false },
    { text: "M.A.77", match: true },
    { text: " or ", match: false },
    { text: "MA77", match: true },
    { text: ".", match: false },
  ]);
  assert.deepEqual(highlight("A man paid 77 coins", ["ma77"]), [
    { text: "A man paid 77 coins", match: false },
  ]);
});

test("highlight returns the text whole when no word matches", () => {
  assert.deepEqual(highlight("A torch", ["dragon"]), [
    { text: "A torch", match: false },
  ]);
  assert.deepEqual(highlight("", ["dragon"]), []);
});
