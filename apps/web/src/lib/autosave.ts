export type SaveOutcome =
  | { ok: true; revision: number }
  | { ok: false; kind: "stale" | "failed"; message: string };

export type SaveState =
  | { status: "idle" }
  | { status: "saving" }
  | { status: "saved" }
  | { status: "error"; kind: "stale" | "failed"; message: string };

export type Timers = {
  set: (fn: () => void, ms: number) => unknown;
  clear: (handle: unknown) => void;
};

const browserTimers: Timers = {
  set: (fn, ms) => setTimeout(fn, ms),
  clear: handle => clearTimeout(handle as ReturnType<typeof setTimeout>),
};

/**
 * Debounced autosave for one section. Saves run one at a time. Each save sends the revision the
 * previous save returned. A failed save keeps the latest document so `retry` can send it. A stale
 * revision is final: the section changed elsewhere, so the editor must reload.
 */
export function createAutosaver<Doc>(options: {
  revision: number;
  save: (doc: Doc, expectedRevision: number) => Promise<SaveOutcome>;
  onState: (state: SaveState) => void;
  delayMs?: number;
  timers?: Timers;
}) {
  const { save, onState, delayMs = 1000, timers = browserTimers } = options;
  let revision = options.revision;
  let latest: Doc | undefined;
  let dirty = false;
  let stale = false;
  let timer: unknown;
  let running: Promise<void> | undefined;

  async function run() {
    while (dirty && !stale) {
      const snapshot = latest as Doc;
      onState({ status: "saving" });
      let outcome: SaveOutcome;
      try {
        outcome = await save(snapshot, revision);
      } catch (error) {
        outcome = {
          ok: false,
          kind: "failed",
          message: error instanceof Error ? error.message : "Could not save.",
        };
      }
      if (!outcome.ok) {
        stale = outcome.kind === "stale";
        onState({
          status: "error",
          kind: outcome.kind,
          message: outcome.message,
        });
        return;
      }
      revision = outcome.revision;
      // Edits made while saving need another save.
      dirty = latest !== snapshot;
    }
    if (!stale) onState({ status: "saved" });
  }

  function start() {
    if (running) return running;
    running = run().finally(() => {
      running = undefined;
    });
    return running;
  }

  return {
    change(doc: Doc) {
      latest = doc;
      dirty = true;
      if (stale) return;
      onState({ status: "saving" });
      timers.clear(timer);
      timer = timers.set(() => void start(), delayMs);
    },
    /** Sends pending edits now, for example on blur or before leaving the page. */
    flush() {
      timers.clear(timer);
      return start() ?? Promise.resolve();
    },
    retry() {
      timers.clear(timer);
      return start();
    },
    dispose() {
      timers.clear(timer);
    },
  };
}
