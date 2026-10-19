import {
  queryOptions,
  useMutation,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query";
import {
  archiveNote,
  createNote,
  getNote,
  listNotes,
  renameNote,
  restoreNote,
  saveNoteBody,
} from "@atlas/api-client";

import type { BlockNoteDocument } from "../lib/blocknote-schema";
import type { SaveOutcome } from "../lib/autosave.ts";

import { rpcOptions } from "../lib/rpc.ts";

type Meta = Parameters<typeof rpcOptions>[0];

export function notesQueryOptions(campaignId: string, archived = false) {
  return queryOptions({
    queryKey: ["notes", campaignId, { archived }],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await listNotes({
        ...config,
        input: { campaignId, archived },
        fields: ["id", "title"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not load the notes."
        );
      return result.data;
    },
    retry: false,
  });
}

export function useNotesList(campaignId: string, archived: boolean) {
  return useSuspenseQuery(notesQueryOptions(campaignId, archived));
}

/** Archives or restores a note from the list. Both views refetch. */
export function useNoteArchive(campaignId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (
      { id, archive }: { id: string; archive: boolean },
      { meta }
    ) => {
      const options = {
        ...rpcOptions(meta),
        identity: id,
        fields: ["id"] as ["id"],
      };
      const result = archive
        ? await archiveNote(options)
        : await restoreNote(options);
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not update the note."
        );
      return result.data;
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["notes", campaignId] }),
  });
}

// No list refetch here: the list route reloads on every visit, and a refetch would flash the
// new note in the list before the note page opens.
export function useNoteCreate(campaignId: string) {
  return useMutation({
    mutationFn: async (_: void, { meta }) => {
      const result = await createNote({
        ...rpcOptions(meta),
        input: { campaignId, title: "Untitled note" },
        fields: ["id"],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not create the note."
        );
      return result.data;
    },
  });
}

export function noteQueryOptions(noteId: string) {
  return queryOptions({
    queryKey: ["note", noteId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await getNote({
        ...config,
        getBy: { id: noteId },
        fields: ["id", "campaignId", "title", "bodyJson", "bodyRevision"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(result.errors[0]?.message ?? "Note not found.");
      return result.data;
    },
    // The editor owns the document after load. A refetch must not replace it.
    staleTime: Infinity,
    retry: false,
  });
}

export function useNote(noteId: string) {
  return useSuspenseQuery(noteQueryOptions(noteId));
}

export function useNoteRename(campaignId: string, noteId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (title: string, { meta }) => {
      const result = await renameNote({
        ...rpcOptions(meta),
        identity: noteId,
        input: { title },
        fields: ["title"],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not rename the note."
        );
      return result.data;
    },
    // Refetching the note would hand the open editor an older body revision.
    onSuccess: ({ title }) => {
      queryClient.setQueryData(
        noteQueryOptions(noteId).queryKey,
        note => note && { ...note, title }
      );
      return queryClient.invalidateQueries({ queryKey: ["notes", campaignId] });
    },
  });
}

export async function saveNoteDocument(
  meta: Meta,
  noteId: string,
  json: BlockNoteDocument,
  expectedRevision: number
): Promise<SaveOutcome> {
  let result;
  try {
    result = await saveNoteBody({
      ...rpcOptions(meta),
      identity: noteId,
      input: { json, schemaVersion: 1, expectedRevision },
      fields: ["bodyRevision"],
    });
  } catch {
    return {
      ok: false,
      kind: "failed",
      message: "Could not reach the server. Your edits are kept. Try again.",
    };
  }

  if (result.success) return { ok: true, revision: result.data.bodyRevision };
  const error = result.errors[0];
  return {
    ok: false,
    kind: error?.type === "stale_revision" ? "stale" : "failed",
    message: error?.message ?? "Could not save.",
  };
}
