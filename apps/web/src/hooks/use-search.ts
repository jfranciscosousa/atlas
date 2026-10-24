import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { search } from "@atlas/api-client";

import type { SearchResponse } from "../lib/search.ts";

import { rpcQuery } from "../lib/rpc-query.ts";

export function searchQueryOptions(query: string, limit: number) {
  return rpcQuery(
    search,
    async run => {
      const result = await run({ input: { query, limit } });
      return result.success
        ? { success: true as const, data: result.data as SearchResponse }
        : result;
    },
    {
      fallback: "Could not search.",
      // Entries change often, and a search is cheap to repeat.
      staleTime: 10_000,
    }
  );
}

/** Searches all campaigns the person may read. A blank query does not search. */
export function useSearch(query: string, limit = 20) {
  return useQuery({
    ...searchQueryOptions(query, limit),
    enabled: query.length > 0,
    // The old results stay on screen while the next ones load, so the list never flashes.
    placeholderData: keepPreviousData,
  });
}
