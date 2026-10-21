import { test } from "node:test";
import assert from "node:assert/strict";

import {
  classifyFrame,
  createSaveTracker,
  type SaveState,
} from "./save-tracker.ts";

function setup() {
  const seen: SaveState[] = [];
  const tracker = createSaveTracker(state => seen.push(state));
  tracker.setOnline(true);
  return { tracker, seen };
}

test("classifyFrame tracks sync step 2 and update only", () => {
  assert.equal(classifyFrame(new Uint8Array([0, 0, 1])), undefined);
  assert.equal(classifyFrame(new Uint8Array([0, 1, 0])), "step2");
  assert.equal(classifyFrame(new Uint8Array([0, 2, 0])), "update");
  assert.equal(classifyFrame(new Uint8Array([1, 2, 0])), undefined);
  assert.equal(classifyFrame(new Uint8Array([])), undefined);
});

test("the state is idle until a local edit", () => {
  const { tracker } = setup();
  assert.equal(tracker.state(), "idle");
  tracker.send("step2").ok();
  assert.equal(tracker.state(), "idle");
});

test("an edit is saving until the ok reply, then saved", () => {
  const { tracker, seen } = setup();
  tracker.edit();
  assert.equal(tracker.state(), "saving");
  const push = tracker.send("update");
  assert.equal(tracker.state(), "saving");
  push.ok();
  assert.equal(tracker.state(), "saved");
  assert.deepEqual(seen, ["saving", "saved"]);
});

test("an edit made after a push stays saving after that push's reply", () => {
  const { tracker } = setup();
  tracker.edit();
  const first = tracker.send("update");
  tracker.edit();
  first.ok();
  assert.equal(tracker.state(), "saving");
  tracker.send("update").ok();
  assert.equal(tracker.state(), "saved");
});

test("an error or timeout reply fails, and a later update ok does not hide it", () => {
  const { tracker } = setup();
  tracker.edit();
  tracker.send("update").fail();
  assert.equal(tracker.state(), "failed");
  tracker.edit();
  tracker.send("update").ok();
  assert.equal(tracker.state(), "failed");
});

test("a step 2 ok closes a failure", () => {
  const { tracker } = setup();
  tracker.edit();
  tracker.send("update").fail();
  tracker.send("step2").ok();
  assert.equal(tracker.state(), "saved");
});

test("offline edits are unsaved-offline until the step 2 after reconnect gets ok", () => {
  const { tracker } = setup();
  tracker.edit();
  tracker.send("update").ok();
  tracker.setOnline(false);
  assert.equal(tracker.state(), "saved");
  tracker.edit();
  assert.equal(tracker.state(), "unsaved-offline");
  tracker.setOnline(true);
  assert.equal(tracker.state(), "saving");
  tracker.send("step2").ok();
  assert.equal(tracker.state(), "saved");
});

test("a push that fails while the connection is down shows unsaved-offline", () => {
  const { tracker } = setup();
  tracker.edit();
  const push = tracker.send("update");
  tracker.setOnline(false);
  push.fail();
  assert.equal(tracker.state(), "unsaved-offline");
});
