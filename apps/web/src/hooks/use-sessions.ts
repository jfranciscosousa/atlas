import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createSession,
  getSession,
  listSessions,
  updateSessionDetails,
} from "@atlas/api-client";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

export type SessionSection = "log" | "prep";

const sessionsKey = (campaignId: string) =>
  rpcKey(listSessions, { input: { campaignId } });

export function sessionsQueryOptions(campaignId: string) {
  return rpcQuery(
    listSessions,
    run =>
      run({
        input: { campaignId },
        fields: ["id", "number", "title", "playedOn", "status"],
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
          "status",
          "logJson",
          "prepJson",
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
    (
      run,
      input: {
        title?: string | null;
        playedOn?: string | null;
        status?: "in_prep" | "done";
      }
    ) =>
      run({
        identity: sessionId,
        input,
        fields: ["title", "playedOn", "status"],
      }),
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
