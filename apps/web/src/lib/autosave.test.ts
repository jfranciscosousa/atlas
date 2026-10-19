import { test } from "node:test";
import assert from "node:assert/strict";

import {
  createAutosaver,
  type SaveOutcome,
  type SaveState,
  type Timers,
} from "./autosave.ts";

function harness(
  save: (doc: string, expected: number) => Promise<SaveOutcome>,
  revision = 0
) {
  const pending = new Map<number, () => void>();
  let nextId = 0;
  const timers: Timers = {
    set: fn => {
      pending.set(++nextId, fn);
      return nextId;
    },
    clear: handle => void pending.delete(handle as number),
  };
  const states: SaveState[] = [];
  const saver = createAutosaver<string>({
    revision,
    save,
    onState: state => states.push(state),
    timers,
  });
  const fire = () => {
    const fns = [...pending.values()];
    pending.clear();
    fns.forEach(fn => fn());
  };
  return { saver, states, fire, pending };
}

test("typing waits for the debounce, then saves once and reports Saving then Saved", async () => {
  const calls: Array<[string, number]> = [];
  const h = harness(async (doc, expected) => {
    calls.push([doc, expected]);
    return { ok: true, revision: expected + 1 };
  });

  h.saver.change("a");
  h.saver.change("ab");
  assert.equal(calls.length, 0);
  assert.equal(h.pending.size, 1);

  h.fire();
  await h.saver.flush();

  assert.deepEqual(calls, [["ab", 0]]);
  assert.equal(h.states.at(-1)?.status, "saved");
  assert.equal(h.states[0]?.status, "saving");
});

test("each save sends the revision returned by the previous one", async () => {
  const expected: number[] = [];
  const h = harness(async (_doc, rev) => {
    expected.push(rev);
    return { ok: true, revision: rev + 1 };
  }, 4);

  h.saver.change("one");
  await h.saver.flush();
  h.saver.change("two");
  await h.saver.flush();

  assert.deepEqual(expected, [4, 5]);
});

test("edits made during a save are saved afterwards with the new revision", async () => {
  const calls: Array<[string, number]> = [];
  let release!: () => void;
  const gate = new Promise<void>(resolve => (release = resolve));
  const h = harness(async (doc, rev) => {
    calls.push([doc, rev]);
    if (calls.length === 1) await gate;
    return { ok: true, revision: rev + 1 };
  });

  h.saver.change("first");
  const first = h.saver.flush();
  h.saver.change("second");
  release();
  await first;

  assert.deepEqual(calls, [
    ["first", 0],
    ["second", 1],
  ]);
  assert.equal(h.states.at(-1)?.status, "saved");
});

test("a failed save keeps the edits, shows an error, and retry sends them again", async () => {
  let fail = true;
  const calls: Array<[string, number]> = [];
  const h = harness(async (doc, rev) => {
    calls.push([doc, rev]);
    return fail
      ? { ok: false, kind: "failed", message: "Network down" }
      : { ok: true, revision: rev + 1 };
  });

  h.saver.change("draft");
  await h.saver.flush();
  assert.deepEqual(h.states.at(-1), {
    status: "error",
    kind: "failed",
    message: "Network down",
  });

  fail = false;
  await h.saver.retry();

  assert.deepEqual(calls, [
    ["draft", 0],
    ["draft", 0],
  ]);
  assert.equal(h.states.at(-1)?.status, "saved");
});

test("a thrown error becomes a failed state and keeps the edits", async () => {
  const h = harness(async () => {
    throw new Error("boom");
  });
  h.saver.change("x");
  await h.saver.flush();
  assert.deepEqual(h.states.at(-1), {
    status: "error",
    kind: "failed",
    message: "boom",
  });
});

test("a stale revision stops further saves", async () => {
  let calls = 0;
  const h = harness(async () => {
    calls++;
    return { ok: false, kind: "stale", message: "Changed elsewhere" };
  });

  h.saver.change("x");
  await h.saver.flush();
  h.saver.change("xy");
  await h.saver.flush();
  await h.saver.retry();

  assert.equal(calls, 1);
  assert.equal(h.states.at(-1)?.status, "error");
});
