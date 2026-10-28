import type { QueryClient } from "@tanstack/react-query";

export const POLL_MS = 3000;
export const IDLE_MS = 60_000;

const INPUT_EVENTS = [
  "pointerdown",
  "pointermove",
  "keydown",
  "wheel",
  "touchstart",
] as const;

/**
 * Polls only while the person is looking at the page: the tab is visible, the window has focus,
 * and the last input is less than `idleMs` old. React Query already pauses polling in a hidden
 * tab. Otherwise the interval returns `false`. React Query does not restart a stopped interval
 * by itself, so a return to the window, or the first input after idle, refetches the active
 * queries and restarts it.
 */
export function pollWhileActive(
  queryClient: QueryClient,
  target: EventTarget,
  {
    idleMs = IDLE_MS,
    now = Date.now,
    hasFocus = () => document.hasFocus(),
  } = {}
) {
  let lastInput = now();
  const idle = () => now() - lastInput >= idleMs;
  const resume = () => void queryClient.refetchQueries({ type: "active" });

  const onInput = () => {
    const wasIdle = idle();
    lastInput = now();
    // Pointer moves over an unfocused window are not a return: the focus event resumes polling.
    if (wasIdle && hasFocus()) resume();
  };
  for (const name of INPUT_EVENTS)
    target.addEventListener(name, onInput, { passive: true });

  target.addEventListener("focus", () => {
    lastInput = now();
    resume();
  });

  return () => (hasFocus() && !idle() ? POLL_MS : false);
}
