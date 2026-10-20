import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createSession,
  getSession,
  listSessions,
  saveSessionLog,
  saveSessionPrep,
  updateSessionDetails,
} from "@atlas/api-client";

import type { BlockNoteDocument } from "../lib/blocknote-schema";
import type { SaveOutcome } from "../lib/autosave.ts";

import { rpcOptions } from "../lib/rpc.ts";
import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

export type SessionSection = "log" | "prep";
type Meta = Parameters<typeof rpcOptions>[0];

const sessionsKey = (campaignId: string) =>
  rpcKey(listSessions, { input: { campaignId } });

export function sessionsQueryOptions(campaignId: string) {
  return rpcQuery(
    listSessions,
    run =>
      run({
        input: { campaignId },
        fields: ["id", "number", "title", "playedOn"],
      }),
    { fallback: "Could not load the sessions." }
  );
}

export function useSessionsList(campaignId: string) {
  return useSuspenseQuery(sessionsQueryOptions(campaignId));
}

// No list refetch here: the list route reloads on every visit, and a refetch would flash the
// new session in the list before its page opens.
export function useSessionCreate(campaignId: string) {
  return useRpcMutation(
    createSession,
    (run, _: void) => run({ input: { campaignId }, fields: ["id"] }),
    { fallback: "Could not create the session." }
  );
}

// A player's request for the prep fields comes back empty. Only the GM's page reads them.
export function sessionQueryOptions(sessionId: string) {
  return rpcQuery(
    getSession,
    run =>
      run({
        getBy: { id: sessionId },
        fields: [
          "id",
          "campaignId",
          "number",
          "title",
          "playedOn",
          "logJson",
          "logRevision",
          "prepJson",
          "prepRevision",
        ],
      }),
    {
      fallback: "Session not found.",
      // The editors own the documents after load. A refetch must not replace them.
      staleTime: Infinity,
    }
  );
}

export function useSession(sessionId: string) {
  return useSuspenseQuery(sessionQueryOptions(sessionId));
}

export function useSessionDetails(campaignId: string, sessionId: string) {
  return useRpcMutation(
    updateSessionDetails,
    (run, input: { title?: string | null; playedOn?: string | null }) =>
      run({ identity: sessionId, input, fields: ["title", "playedOn"] }),
    {
      fallback: "Could not update the session.",
      // Refetching the session would hand the open editors an older revision.
      onSuccess: (details, queryClient) =>
        queryClient.setQueryData(
          sessionQueryOptions(sessionId).queryKey,
          session => session && { ...session, ...details }
        ),
      invalidate: [sessionsKey(campaignId)],
    }
  );
}

export async function saveSessionDocument(
  meta: Meta,
  sessionId: string,
  section: SessionSection,
  json: BlockNoteDocument,
  expectedRevision: number
): Promise<SaveOutcome> {
  const input = { json, schemaVersion: 1, expectedRevision };
  const config = { ...rpcOptions(meta), identity: sessionId, input };
  let result;
  try {
    result =
      section === "log"
        ? await saveSessionLog({ ...config, fields: ["logRevision"] })
        : await saveSessionPrep({ ...config, fields: ["prepRevision"] });
  } catch {
    return {
      ok: false,
      kind: "failed",
      message: "Could not reach the server. Your edits are kept. Try again.",
    };
  }

  if (result.success) {
    const data = result.data as Record<string, number>;
    return { ok: true, revision: data.logRevision ?? data.prepRevision! };
  }
  const error = result.errors[0];
  return {
    ok: false,
    kind: error?.type === "stale_revision" ? "stale" : "failed",
    message: error?.message ?? "Could not save.",
  };
}
