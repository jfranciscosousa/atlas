import * as Y from "yjs";
import { PhoenixChannelProvider } from "y-phoenix-channel";

import {
  classifyFrame,
  createSaveTracker,
  type SaveState,
} from "./save-tracker";
import { whoIsHere, type Person } from "./presence";
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
  /** The other people who have the section open. */
  onPresence: (people: Person[]) => void;
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
  // The server names this person in the join reply. Their other tabs must not show as "also here".
  let selfKey: string | undefined;
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
    .receive(
      "ok",
      (reply: { canWrite: boolean; epoch: number; key: string }) => {
        // A rejoin that finds a new epoch means our document belongs to a lost history.
        if (epoch !== undefined && epoch !== reply.epoch)
          return end({ kind: "reset" });
        epoch = reply.epoch;
        selfKey = reply.key;
        publishPresence();
        handlers.onPermissions(reply.canWrite);
      }
    )
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
      // The server relays awareness: it sets the names, and a client sends only its cursor.
      // No other tab may see this document.
      disableBc: true,
      updateThrottle: 100,
      awarenessThrottle: 100,
      // A periodic sync heals any update a delivery missed.
      resyncInterval: 30_000,
    }
  );

  const publishPresence = () =>
    handlers.onPresence(
      whoIsHere(provider.awareness.getStates(), doc.clientID, selfKey)
    );
  provider.awareness.on("change", publishPresence);

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
