import { useSuspenseQuery } from "@tanstack/react-query";
import {
  type CreateEntryFieldInput,
  type UpdateEntryFieldInput,
  archiveEntryField,
  createEntryField,
  getEntry,
  listEntries,
  listEntryFields,
  moveEntryField,
  restoreEntryField,
  updateEntryField,
} from "@atlas/api-client";

import type { EntryKind } from "../lib/entry-kinds.ts";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

const fieldsKey = (campaignId: string) =>
  rpcKey(listEntryFields, { input: { campaignId } });

// A field change alters what an entry shows and what a list keeps.
const dependents = (campaignId: string) => [
  fieldsKey(campaignId),
  rpcKey(getEntry),
  rpcKey(listEntries, { input: { campaignId } }),
];

const FIELD_ATTRIBUTES = [
  "id",
  "campaignId",
  "kind",
  "label",
  "type",
  "options",
  "gmOnly",
  "position",
  "archivedAt",
] as const;

/**
 * The custom fields of a campaign in order. The GM gets every field; a player gets the active
 * ones that are not GM-only. `archived` lists the archived fields (the GM only).
 */
export function entryFieldsQueryOptions(
  campaignId: string,
  options: { kind?: EntryKind; archived?: boolean } = {}
) {
  const { kind, archived = false } = options;
  return rpcQuery(
    listEntryFields,
    run =>
      run({
        input: { campaignId, archived, ...(kind && { kind }) },
        fields: [...FIELD_ATTRIBUTES],
      }),
    { fallback: "Could not load the custom fields." }
  );
}

export function useEntryFields(
  campaignId: string,
  options: { kind?: EntryKind; archived?: boolean } = {}
) {
  return useSuspenseQuery(entryFieldsQueryOptions(campaignId, options));
}

export type EntryFieldRecord = ReturnType<
  typeof useEntryFields
>["data"][number];

/** The choices of a select, from `options`. */
export const fieldChoices = (field: { options: Record<string, any> }) =>
  (field.options.choices as string[] | undefined) ?? [];

/** The kind that an entry field points to. */
export const fieldTargetKind = (field: { options: Record<string, any> }) =>
  field.options.target_kind as EntryKind | undefined;

export type NewEntryField = Omit<CreateEntryFieldInput, "campaignId">;

export function useEntryFieldCreate(campaignId: string) {
  return useRpcMutation(
    createEntryField,
    (run, field: NewEntryField) =>
      run({ input: { campaignId, ...field }, fields: ["id"] }),
    {
      fallback: "Could not add the field.",
      invalidate: dependents(campaignId),
    }
  );
}

export function useEntryFieldUpdate(campaignId: string) {
  return useRpcMutation(
    updateEntryField,
    (run, { id, ...changes }: { id: string } & UpdateEntryFieldInput) =>
      run({ identity: id, input: changes, fields: ["id"] }),
    {
      fallback: "Could not change the field.",
      invalidate: dependents(campaignId),
    }
  );
}

export function useEntryFieldMove(campaignId: string) {
  return useRpcMutation(
    moveEntryField,
    (run, { id, position }: { id: string; position: number }) =>
      run({ identity: id, input: { position }, fields: ["id"] }),
    {
      fallback: "Could not move the field.",
      invalidate: dependents(campaignId),
    }
  );
}

export function useEntryFieldArchive(campaignId: string) {
  return useRpcMutation(
    archiveEntryField,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not archive the field.",
      invalidate: dependents(campaignId),
    }
  );
}

export function useEntryFieldRestore(campaignId: string) {
  return useRpcMutation(
    restoreEntryField,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not restore the field.",
      invalidate: dependents(campaignId),
    }
  );
}
