import { useSuspenseQuery } from "@tanstack/react-query";
import { createPlayerLog, listPlayerLogs } from "@atlas/api-client";

import { rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

const fields = ["id", "isMine", "authorName", "bodyJson"] as const;

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
