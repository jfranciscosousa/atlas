import { useSuspenseQuery } from "@tanstack/react-query";
import {
  getMcpClient,
  listMcpConnections,
  revokeMcpConnection,
} from "@atlas/api-client";

import { rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

const fields = ["id", "clientName", "insertedAt", "lastUsedAt"] as const;

export function mcpConnectionsQueryOptions(userId: string) {
  return rpcQuery(listMcpConnections, run => run({ fields: [...fields] }), {
    fallback: "Could not load your MCP connections.",
    scope: userId,
  });
}

export function useMcpConnections(userId: string) {
  return useSuspenseQuery(mcpConnectionsQueryOptions(userId));
}

export function useMcpConnectionRevoke(userId: string) {
  return useRpcMutation(
    revokeMcpConnection,
    (run, id: string) => run({ identity: id }),
    {
      fallback: "Could not revoke the connection.",
      invalidate: [mcpConnectionsQueryOptions(userId).queryKey],
    }
  );
}

export function mcpClientQueryOptions(clientId: string) {
  return rpcQuery(
    getMcpClient,
    run => run({ getBy: { id: clientId }, fields: ["name"] }),
    { fallback: "This app is not known to Atlas." }
  );
}
