import { test } from "node:test";
import assert from "node:assert/strict";

import { summarize, whoIsHere } from "./presence.ts";

const user = (key: string, name: string) => ({
  user: { key, name, color: "#16a34a" },
});

test("whoIsHere lists others by name, once per person", () => {
  const states = new Map<number, unknown>([
    [1, user("self", "Me")],
    [2, user("b", "Bob")],
    [3, { ...user("a", "Ann"), cursor: { anchor: {}, head: {} } }],
    [4, user("a", "Ann")], // a second tab of Ann
  ]);
  assert.deepEqual(
    whoIsHere(states, 1, "self").map(p => p.name),
    ["Ann", "Bob"]
  );
});

test("whoIsHere hides the own person in another tab and the own client", () => {
  const states = new Map<number, unknown>([
    [1, user("self", "Me")],
    [2, user("self", "Me")],
  ]);
  assert.deepEqual(whoIsHere(states, 1, "self"), []);
  // Before the join reply the own key is unknown: the other tab shows until it is known.
  assert.equal(whoIsHere(states, 1, undefined).length, 1);
});

test("whoIsHere skips states without a server-set identity", () => {
  const states = new Map<number, unknown>([
    [2, null],
    [3, {}],
    [4, { user: { name: "No key", color: "#000" } }],
    [5, { user: { key: 1, name: "Number", color: "#000" } }],
    [6, { cursor: {} }],
  ]);
  assert.deepEqual(whoIsHere(states, 1, "self"), []);
});

test("summarize shows five people and counts the rest", () => {
  const people = Array.from({ length: 8 }, (_, i) => ({
    key: `k${i}`,
    name: `P${i}`,
    color: "#000",
  }));
  assert.equal(summarize(people).shown.length, 5);
  assert.equal(summarize(people).more, 3);
  assert.equal(summarize(people.slice(0, 2)).more, 0);
});
