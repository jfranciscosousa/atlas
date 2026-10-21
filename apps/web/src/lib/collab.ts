import * as Y from "yjs";
import { PhoenixChannelProvider } from "y-phoenix-channel";

import {
  classifyFrame,
  createSaveTracker,
  type SaveState,
} from "./save-tracker";
import { connectSocket } from "./collab-socket";

/** The Yjs root BlockNote edits. The server projects the same root to JSON. */
export const FRAGMENT = "document-store";

export type CollabNotice =
  | { kind: "revoked" } // access ended
  | { kind: "reset" } // the text was replaced by a save outside live editing
  | { kind: "rejected"; reason: string }; // the server refused a change

export type CollabStatus = "connecting" | "synced" | "offline";

export type Collab = {
  doc: Y.Doc;
  provider: PhoenixChannelProvider;
  /** True while edits made offline have not reached the server. */
  hasUnsyncedEdits: () => boolean;
  destroy: () => void;
};

type Handlers = {
  onStatus: (status: CollabStatus) => void;
  onPermissions: (canWrite: boolean) => void;
  onNotice: (notice: CollabNotice) => void;
  onSaveState: (state: SaveState) => void;
};

/**
 * Joins `kind:id:section` and syncs a new Yjs document with the server. The server checks the
 * user's rights on every message, so a notice of `revoked` means the user lost access.
 */
export function openDocument(
  ref: string,
  token: string,
  handlers: Handlers
): Collab {
  const doc = new Y.Doc();
  const channel = connectSocket(token).channel(`doc:${ref}`, {});
  let epoch: number | undefined;
  let everSynced = false;
  let unsynced = false;
  let ended = false;
  const saves = createSaveTracker(handlers.onSaveState);

  // The provider ignores the reply to a push. Follow the replies of the pushes that store edits.
  const push = channel.push.bind(channel);
  channel.push = (event, payload, timeout) => {
    const sent = push(event, payload, timeout);
    const kind =
      payload instanceof ArrayBuffer
        ? classifyFrame(new Uint8Array(payload))
        : undefined;
    if (!kind) return sent;
    const save = saves.send(kind);
    return sent
      .receive("ok", save.ok)
      .receive("error", save.fail)
      .receive("timeout", save.fail);
  };

  const end = (notice: CollabNotice) => {
    if (ended) return;
    ended = true;
    handlers.onNotice(notice);
    collab.destroy();
  };

  // Join before the provider attaches: it reads `channel.joinPush` and never joins itself.
  channel
    .join()
    .receive("ok", (reply: { canWrite: boolean; epoch: number }) => {
      // A rejoin that finds a new epoch means our document belongs to a lost history.
      if (epoch !== undefined && epoch !== reply.epoch)
        return end({ kind: "reset" });
      epoch = reply.epoch;
      handlers.onPermissions(reply.canWrite);
    })
    .receive("error", () => end({ kind: "revoked" }));
  channel.on("permissions", (reply: { canWrite: boolean }) =>
    handlers.onPermissions(reply.canWrite)
  );
  channel.on("revoked", () => end({ kind: "revoked" }));
  channel.on("reset", () => end({ kind: "reset" }));
  channel.on("rejected", (reply: { reason: string }) =>
    handlers.onNotice({ kind: "rejected", reason: reply.reason })
  );

  const provider = new PhoenixChannelProvider(
    connectSocket(token),
    channel.topic,
    doc,
    {
      channel,
      // Awareness (cursors) is not relayed, and no other tab may see this document.
      disableBc: true,
      updateThrottle: 100,
      // A periodic sync heals any update a delivery missed.
      resyncInterval: 30_000,
    }
  );

  provider.on("sync", (synced: boolean) => {
    if (synced) {
      everSynced = true;
      unsynced = false;
    }
    saves.setOnline(synced);
    handlers.onStatus(
      synced ? "synced" : everSynced ? "offline" : "connecting"
    );
  });
  doc.on("update", (_update: Uint8Array, origin: unknown) => {
    if (origin === provider) return;
    saves.edit();
    if (channel.state !== "joined") unsynced = true;
  });

  const collab: Collab = {
    doc,
    provider,
    hasUnsyncedEdits: () => unsynced,
    destroy: () => {
      provider.awareness.destroy();
      provider.destroy();
      doc.destroy();
    },
  };
  return collab;
}
