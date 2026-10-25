import type { QueryClient } from "@tanstack/react-query";

import { notFound } from "@tanstack/react-router";

import {
  entriesQueryOptions,
  entryKindsQueryOptions,
  entryQueryOptions,
  entryRelationsQueryOptions,
} from "../hooks/use-entries.ts";
import { charactersQueryOptions } from "../hooks/use-characters.ts";
import { campaignQueryOptions } from "../hooks/use-campaigns.ts";

/**
 * Loads what an entry page reads. Saving does not update the cached entry, so the entry and its
 * relations load again on every visit. In preview the entry must be one that players read.
 */
export async function loadEntryPage(
  queryClient: QueryClient,
  params: { campaignId: string; entryId: string },
  preview: boolean
) {
  try {
    const [, , , , entry] = await Promise.all([
      queryClient.ensureQueryData(campaignQueryOptions(params.campaignId)),
      queryClient.ensureQueryData(charactersQueryOptions(params.campaignId)),
      queryClient.ensureQueryData(entryKindsQueryOptions()),
      queryClient.fetchQuery({
        ...entriesQueryOptions(params.campaignId),
        staleTime: 0,
      }),
      queryClient.fetchQuery({
        ...entryQueryOptions(params.entryId),
        staleTime: 0,
      }),
      queryClient.fetchQuery({
        ...entryRelationsQueryOptions(params.campaignId, params.entryId),
        staleTime: 0,
      }),
    ]);
    // The URL must name the campaign the entry belongs to.
    if (entry.campaignId !== params.campaignId) throw new Error("mismatch");
    // A player cannot open a hidden or an archived entry, so neither can the preview.
    if (preview && !entry.shown) throw new Error("not shown");
  } catch {
    throw notFound();
  }
}
