import { test } from "node:test";
import assert from "node:assert/strict";
import { QueryClient } from "@tanstack/react-query";

import { IDLE_MS, POLL_MS, pollWhileActive } from "./polling.ts";

function setup() {
  let time = 0;
  let focused = true;
  const target = new EventTarget();
  const client = new QueryClient();
  let refetches = 0;
  client.refetchQueries = (() => {
    refetches++;
    return Promise.resolve();
  }) as typeof client.refetchQueries;
  const interval = pollWhileActive(client, target, {
    now: () => time,
    hasFocus: () => focused,
  });
  return {
    interval,
    target,
    refetches: () => refetches,
    wait: (ms: number) => (time += ms),
    focus: (value: boolean) => {
      focused = value;
      if (value) target.dispatchEvent(new Event("focus"));
    },
  };
}

test("polls while the person is active", () => {
  const { interval, wait } = setup();
  wait(IDLE_MS - 1);
  assert.equal(interval(), POLL_MS);
});

test("stops polling after the idle time", () => {
  const { interval, wait } = setup();
  wait(IDLE_MS);
  assert.equal(interval(), false);
});

test("input keeps the person active and does not refetch", () => {
  const { interval, target, wait, refetches } = setup();
  wait(IDLE_MS - 1);
  target.dispatchEvent(new Event("keydown"));
  wait(IDLE_MS - 1);
  assert.equal(interval(), POLL_MS);
  assert.equal(refetches(), 0);
});

test("the first input after idle refetches and restarts polling", () => {
  const { interval, target, wait, refetches } = setup();
  wait(IDLE_MS);
  target.dispatchEvent(new Event("pointermove"));
  assert.equal(interval(), POLL_MS);
  assert.equal(refetches(), 1);
  target.dispatchEvent(new Event("pointermove"));
  assert.equal(refetches(), 1);
});

test("an unfocused window does not poll, even right after input", () => {
  const { interval, target, focus } = setup();
  focus(false);
  target.dispatchEvent(new Event("pointermove"));
  assert.equal(interval(), false);
});

test("pointer moves over an unfocused window do not refetch", () => {
  const { target, wait, focus, refetches } = setup();
  focus(false);
  wait(IDLE_MS);
  target.dispatchEvent(new Event("pointermove"));
  assert.equal(refetches(), 0);
});

test("returning to the window refetches and restarts polling", () => {
  const { interval, wait, focus, refetches } = setup();
  focus(false);
  wait(IDLE_MS);
  focus(true);
  assert.equal(interval(), POLL_MS);
  assert.equal(refetches(), 1);
});
