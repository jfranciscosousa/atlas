/**
 * Follows whether the server committed the local edits of one live document.
 * "Saved" means the server answered every sync push `ok` after it stored the change.
 */
export type SaveState =
  | "idle" // no local edit yet
  | "saving" // a local edit has no ok reply yet
  | "saved" // every local edit has an ok reply
  | "failed" // the server refused a push or did not answer
  | "unsaved-offline"; // the connection is down and local edits are not saved

/** A push that stores edits. `step2` carries everything the server lacked. */
export type PushKind = "step2" | "update";

/**
 * Names a Yjs frame that carries an update. Sync step 1 and awareness frames return undefined.
 * Frame layout: message type (0 = sync), then sync type (0 = step 1, 1 = step 2, 2 = update).
 */
export function classifyFrame(frame: Uint8Array): PushKind | undefined {
  if (frame[0] !== 0) return undefined;
  if (frame[1] === 1) return "step2";
  if (frame[1] === 2) return "update";
  return undefined;
}

export type Push = { ok: () => void; fail: () => void };

export type SaveTracker = {
  state: () => SaveState;
  /** A local edit happened. */
  edit: () => void;
  /** The connection is up (synced) or down. */
  setOnline: (online: boolean) => void;
  /** A push of `kind` just left. It covers every edit made so far. */
  send: (kind: PushKind) => Push;
};

export function createSaveTracker(onChange: (state: SaveState) => void) {
  let edits = 0;
  let saved = 0;
  let failed = false;
  let online = false;
  let last: SaveState = "idle";

  const compute = (): SaveState => {
    const unsaved = failed || saved < edits;
    if (!online && unsaved) return "unsaved-offline";
    if (failed) return "failed";
    if (saved < edits) return "saving";
    return edits ? "saved" : "idle";
  };
  const update = () => {
    const next = compute();
    if (next === last) return;
    last = next;
    onChange(next);
  };

  const tracker: SaveTracker = {
    state: () => last,
    edit: () => {
      edits += 1;
      update();
    },
    setOnline: next => {
      online = next;
      update();
    },
    send: kind => {
      const covered = edits;
      return {
        ok: () => {
          saved = Math.max(saved, covered);
          // A lost update leaves a gap that only step 2 (all the server lacks) closes.
          if (kind === "step2") failed = false;
          update();
        },
        fail: () => {
          failed = true;
          update();
        },
      };
    },
  };
  return tracker;
}
