import type {} from "@tanstack/react-query";

type RpcMeta = { csrfToken: string };

declare module "@tanstack/react-query" {
  interface Register {
    queryMeta: RpcMeta;
    mutationMeta: RpcMeta;
  }
}

export function rpcOptions(meta: RpcMeta | undefined) {
  if (!meta?.csrfToken)
    throw new Error("Your session expired. Reload the page and try again.");

  return {
    headers: { "x-csrf-token": meta.csrfToken },
    fetchOptions: {
      credentials: "same-origin",
      cache: "no-store",
    } satisfies RequestInit,
  };
}
