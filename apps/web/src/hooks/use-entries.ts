import { useSuspenseQuery, type QueryClient } from "@tanstack/react-query";
import {
  archiveEntry,
  createEntry,
  getEntry,
  listEntries,
  renameEntry,
  restoreEntry,
  setEntryHidden,
} from "@atlas/api-client";

import type { EntryKind } from "../lib/entry-kinds.ts";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

// Matches every list of one campaign: by kind, archived, or as a player.
const entriesKey = (campaignId: string) =>
  rpcKey(listEntries, { input: { campaignId } });

type ListOptions = {
  kind?: EntryKind;
  archived?: boolean;
  asPlayer?: boolean;
};

export function entriesQueryOptions(
  campaignId: string,
  options: ListOptions = {}
) {
  const { kind, archived = false, asPlayer = false } = options;
  return rpcQuery(
    listEntries,
    run =>
      run({
        input: {
          campaignId,
          archived,
          // The GM lists what a player reads, for Preview as player.
          ...(asPlayer && { asPlayer }),
          ...(kind && { kind }),
        },
        fields: ["id", "kind", "name", "hidden", "shown"],
      }),
    { fallback: "Could not load the entries." }
  );
}

export function useEntriesList(campaignId: string, options: ListOptions = {}) {
  return useSuspenseQuery(entriesQueryOptions(campaignId, options));
}

export type EntrySection = "description" | "secret_notes";

const ENTRY_FIELDS = [
  "id",
  "campaignId",
  "kind",
  "name",
  "hidden",
  "shown",
  "archivedAt",
  "descriptionJson",
  "secretNotesJson",
] as const;

export function entryQueryOptions(entryId: string) {
  return rpcQuery(
    getEntry,
    run => run({ getBy: { id: entryId }, fields: [...ENTRY_FIELDS] }),
    {
      fallback: "Entry not found.",
      // The editors own the documents after load. A refetch must not replace them.
      staleTime: Infinity,
    }
  );
}

export function useEntry(entryId: string) {
  return useSuspenseQuery(entryQueryOptions(entryId));
}

// Writes update the open entry directly. A refetch would hand an open editor an older revision.
function patchEntry(entryId: string) {
  return <T extends object>(data: T, queryClient: QueryClient) =>
    queryClient.setQueryData(entryQueryOptions(entryId).queryKey, entry =>
      entry ? ({ ...entry, ...data } as typeof entry) : entry
    );
}

const FIELDS_AFTER_WRITE = ["name", "hidden", "shown", "archivedAt"] as const;

// No list refetch after a create: the list route reloads on every visit, and a refetch would
// flash the new entry in the list before its page opens.
export function useEntryCreate(campaignId: string) {
  return useRpcMutation(
    createEntry,
    (run, { kind, name }: { kind: EntryKind; name: string }) =>
      run({ input: { campaignId, kind, name }, fields: ["id"] }),
    { fallback: "Could not create the entry." }
  );
}

export function useEntryRename(campaignId: string, entryId: string) {
  return useRpcMutation(
    renameEntry,
    (run, name: string) =>
      run({ identity: entryId, input: { name }, fields: ["name"] }),
    {
      fallback: "Could not rename the entry.",
      onSuccess: patchEntry(entryId),
      invalidate: [entriesKey(campaignId)],
    }
  );
}

/** Shows an entry to the players, or hides it again. The list and the open entry follow. */
export function useEntryHidden(campaignId: string, entryId: string) {
  return useRpcMutation(
    setEntryHidden,
    (run, hidden: boolean) =>
      run({
        identity: entryId,
        input: { hidden },
        fields: [...FIELDS_AFTER_WRITE],
      }),
    {
      fallback: "Could not update the entry.",
      onSuccess: patchEntry(entryId),
      invalidate: [entriesKey(campaignId)],
    }
  );
}

/**
 * Archives or restores an entry. Every list refetches. Pass the ID of the open entry to update
 * its page too.
 */
export function useEntryArchive(campaignId: string, openEntryId?: string) {
  return useRpcMutation(
    archiveEntry,
    (run, id: string) =>
      run({ identity: id, fields: ["id", "archivedAt", "shown"] }),
    {
      fallback: "Could not update the entry.",
      onSuccess: (data, queryClient) =>
        openEntryId && patchEntry(openEntryId)(data, queryClient),
      invalidate: [entriesKey(campaignId)],
    }
  );
}

export function useEntryRestore(campaignId: string, openEntryId?: string) {
  return useRpcMutation(
    restoreEntry,
    (run, id: string) =>
      run({ identity: id, fields: ["id", "archivedAt", "shown"] }),
    {
      fallback: "Could not update the entry.",
      onSuccess: (data, queryClient) =>
        openEntryId && patchEntry(openEntryId)(data, queryClient),
      invalidate: [entriesKey(campaignId)],
    }
  );
}
