import { useSuspenseQuery, type QueryClient } from "@tanstack/react-query";
import {
  type CreateEntryRelationInput,
  type UpdateEntryInput,
  archiveEntry,
  createEntry,
  createEntryRelation,
  deleteEntryRelation,
  getEntry,
  getEntryKinds,
  listEntries,
  listEntryRelations,
  renameEntry,
  restoreEntry,
  setEntryHidden,
  updateEntry,
} from "@atlas/api-client";

import type { EntryKind, EntryKindsResponse } from "../lib/entry-kinds.ts";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

// Matches every list of one campaign: by kind, archived, or as a player.
const entriesKey = (campaignId: string) =>
  rpcKey(listEntries, { input: { campaignId } });

/** Keeps the entries whose custom field has this value. The value is text, as the API reads it. */
export type CustomFieldFilter = { id: string; value: string };

type ListOptions = {
  kind?: EntryKind;
  archived?: boolean;
  asPlayer?: boolean;
  customField?: CustomFieldFilter;
};

export function entriesQueryOptions(
  campaignId: string,
  options: ListOptions = {}
) {
  const { kind, archived = false, asPlayer = false, customField } = options;
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
          ...(customField && {
            customFieldId: customField.id,
            customFieldValue: customField.value,
          }),
        },
        fields: [
          "id",
          "kind",
          "name",
          "status",
          "hidden",
          "shown",
          "parentId",
          "parentName",
          "imageId",
        ],
      }),
    { fallback: "Could not load the entries." }
  );
}

export function useEntriesList(campaignId: string, options: ListOptions = {}) {
  return useSuspenseQuery(entriesQueryOptions(campaignId, options));
}

/** The statuses, fields and relations of every kind. They never change while the app runs. */
export function entryKindsQueryOptions() {
  return rpcQuery(
    getEntryKinds,
    async run => {
      const result = await run({});
      return result.success
        ? { success: true as const, data: result.data as EntryKindsResponse }
        : result;
    },
    { fallback: "Could not load the kinds of entry.", staleTime: Infinity }
  );
}

export function useEntryKinds() {
  return useSuspenseQuery(entryKindsQueryOptions()).data;
}

export type EntrySection = "description" | "secret_notes";

const ENTRY_FIELDS = [
  "id",
  "campaignId",
  "kind",
  "name",
  "status",
  "hidden",
  "shown",
  "fields",
  "parentId",
  "parentName",
  "parentShown",
  "imageId",
  "archivedAt",
  "customValues",
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

const FIELDS_AFTER_WRITE = [
  "name",
  "status",
  "hidden",
  "shown",
  "fields",
  "parentId",
  "parentName",
  "parentShown",
  "imageId",
  "archivedAt",
  "customValues",
] as const;

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

/** `fields` is merged into the stored fields. A blank value clears one field. */
export type EntryChanges = UpdateEntryInput;

export function useEntryUpdate(campaignId: string, entryId: string) {
  return useRpcMutation(
    updateEntry,
    (run, changes: EntryChanges) =>
      run({
        identity: entryId,
        input: changes,
        fields: [...FIELDS_AFTER_WRITE],
      }),
    {
      fallback: "Could not update the entry.",
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
      invalidate: [entriesKey(campaignId), relationsKey(campaignId)],
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
      invalidate: [entriesKey(campaignId), relationsKey(campaignId)],
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
      invalidate: [entriesKey(campaignId), relationsKey(campaignId)],
    }
  );
}

const relationsKey = (campaignId: string) =>
  rpcKey(listEntryRelations, { input: { campaignId } });

/** The relations of one entry or character, as the signed-in person may read them. */
export function entryRelationsQueryOptions(campaignId: string, endId: string) {
  return rpcQuery(
    listEntryRelations,
    run =>
      run({
        input: { campaignId, endId },
        fields: [
          "id",
          "relation",
          "label",
          "fromKind",
          "fromId",
          "fromName",
          "fromShown",
          "toKind",
          "toId",
          "toName",
          "toShown",
        ],
      }),
    { fallback: "Could not load the relations." }
  );
}

export function useEntryRelations(campaignId: string, endId: string) {
  return useSuspenseQuery(entryRelationsQueryOptions(campaignId, endId));
}

export type NewRelation = Omit<CreateEntryRelationInput, "campaignId">;

export function useRelationCreate(campaignId: string) {
  return useRpcMutation(
    createEntryRelation,
    (run, relation: NewRelation) =>
      run({ input: { campaignId, ...relation }, fields: ["id"] }),
    {
      fallback: "Could not add the relation.",
      invalidate: [relationsKey(campaignId)],
    }
  );
}

export function useRelationDelete(campaignId: string) {
  return useRpcMutation(
    deleteEntryRelation,
    (run, id: string) => run({ identity: id }),
    {
      fallback: "Could not remove the relation.",
      invalidate: [relationsKey(campaignId)],
    }
  );
}
