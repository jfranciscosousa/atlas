import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createPlayerLog,
  listPlayerLogs,
  savePlayerLogBody,
} from "@atlas/api-client";

import type { BlockNoteDocument } from "../lib/blocknote-schema";
import type { SaveOutcome } from "../lib/autosave.ts";

import { rpcOptions } from "../lib/rpc.ts";
import { rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

type Meta = Parameters<typeof rpcOptions>[0];

const fields = [
  "id",
  "isMine",
  "authorName",
  "bodyJson",
  "bodyRevision",
] as const;

export function playerLogsQueryOptions(sessionId: string) {
  return rpcQuery(
    listPlayerLogs,
    run => run({ input: { sessionId }, fields: [...fields] }),
    {
      fallback: "Could not load the player logs.",
      // The editors own the documents after load. A refetch must not replace them.
      staleTime: Infinity,
    }
  );
}

export function usePlayerLogs(sessionId: string) {
  return useSuspenseQuery(playerLogsQueryOptions(sessionId));
}

// The new log joins the cached list at once, so its editor opens without a refetch.
export function usePlayerLogCreate(sessionId: string) {
  return useRpcMutation(
    createPlayerLog,
    (run, _: void) => run({ input: { sessionId }, fields: [...fields] }),
    {
      fallback: "Could not start your log.",
      onSuccess: (log, queryClient) =>
        queryClient.setQueryData(
          playerLogsQueryOptions(sessionId).queryKey,
          logs => logs && [...logs.filter(({ id }) => id !== log.id), log]
        ),
    }
  );
}

export async function savePlayerLogDocument(
  meta: Meta,
  playerLogId: string,
  json: BlockNoteDocument,
  expectedRevision: number
): Promise<SaveOutcome> {
  let result;
  try {
    result = await savePlayerLogBody({
      ...rpcOptions(meta),
      identity: playerLogId,
      input: { json, schemaVersion: 1, expectedRevision },
      fields: ["bodyRevision"],
    });
  } catch {
    return {
      ok: false,
      kind: "failed",
      message: "Could not reach the server. Your edits are kept. Try again.",
    };
  }

  if (result.success) return { ok: true, revision: result.data.bodyRevision };
  const error = result.errors[0];
  return {
    ok: false,
    kind: error?.type === "stale_revision" ? "stale" : "failed",
    message: error?.message ?? "Could not save.",
  };
}
