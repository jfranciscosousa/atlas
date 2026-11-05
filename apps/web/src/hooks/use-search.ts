import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { search } from "@atlas/api-client";

import type { SearchResponse } from "../lib/search.ts";
import type { EntryKind } from "../lib/entry-kinds.ts";

import { rpcQuery } from "../lib/rpc-query.ts";

type SearchScope = {
  campaignId?: string;
  kinds?: readonly EntryKind[];
  /** True finds only archived entries, false only active ones. Omitted finds both. */
  archived?: boolean;
};

type SearchOptions = SearchScope & { offset?: number; staleTime?: number };

export function searchQueryOptions(
  query: string,
  limit: number,
  {
    campaignId,
    kinds,
    archived,
    offset,
    staleTime = 10_000,
  }: SearchOptions = {}
) {
  return rpcQuery(
    search,
    async run => {
      const result = await run({
        input: {
          query,
          limit,
          ...(campaignId && { campaignId }),
          ...(kinds && { kinds: [...kinds] }),
          ...(archived !== undefined && { archived }),
          ...(offset && { offset }),
        },
      });
      return result.success
        ? { success: true as const, data: result.data as SearchResponse }
        : result;
    },
    {
      fallback: "Could not search.",
      // Entries change often, and a search is cheap to repeat.
      staleTime,
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

const scopeOf = (key: readonly unknown[]) => {
  const input = (key[1] as { input?: SearchScope } | undefined)?.input;
  return JSON.stringify([input?.campaignId, input?.kinds, input?.archived]);
};

/**
 * One page of hits in one campaign, for a list that has its own search box. The same search
 * as the quick access menu. The old page stays on screen while the next one loads, unless the
 * kinds or the archived filter change: then it would show the wrong entries.
 */
export function useScopedSearch(
  query: string,
  limit: number,
  options: SearchOptions
) {
  const queryOptions = searchQueryOptions(query, limit, {
    // A list must show entries created since the last visit.
    staleTime: 0,
    ...options,
  });
  return useQuery({
    ...queryOptions,
    enabled: query.length > 0,
    placeholderData: (previous, previousQuery) =>
      previousQuery &&
      scopeOf(previousQuery.queryKey) === scopeOf(queryOptions.queryKey)
        ? previous
        : undefined,
  });
}
