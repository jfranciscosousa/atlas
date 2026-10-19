import { useSuspenseQuery } from "@tanstack/react-query";
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
import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

type Meta = Parameters<typeof rpcOptions>[0];

// Matches the active and the archived list of one campaign.
const notesKey = (campaignId: string) =>
  rpcKey(listNotes, { input: { campaignId } });

export function notesQueryOptions(campaignId: string, archived = false) {
  return rpcQuery(
    listNotes,
    run => run({ input: { campaignId, archived }, fields: ["id", "title"] }),
    { fallback: "Could not load the notes." }
  );
}

export function useNotesList(campaignId: string, archived: boolean) {
  return useSuspenseQuery(notesQueryOptions(campaignId, archived));
}

/** Archives or restores a note from the list. Both views refetch. */
export function useNoteArchive(campaignId: string) {
  return useRpcMutation(
    archiveNote,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not update the note.",
      invalidate: [notesKey(campaignId)],
    }
  );
}

export function useNoteRestore(campaignId: string) {
  return useRpcMutation(
    restoreNote,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not update the note.",
      invalidate: [notesKey(campaignId)],
    }
  );
}

// No list refetch here: the list route reloads on every visit, and a refetch would flash the
// new note in the list before the note page opens.
export function useNoteCreate(campaignId: string) {
  return useRpcMutation(
    createNote,
    (run, _: void) =>
      run({ input: { campaignId, title: "Untitled note" }, fields: ["id"] }),
    { fallback: "Could not create the note." }
  );
}

export function noteQueryOptions(noteId: string) {
  return rpcQuery(
    getNote,
    run =>
      run({
        getBy: { id: noteId },
        fields: ["id", "campaignId", "title", "bodyJson", "bodyRevision"],
      }),
    {
      fallback: "Note not found.",
      // The editor owns the document after load. A refetch must not replace it.
      staleTime: Infinity,
    }
  );
}

export function useNote(noteId: string) {
  return useSuspenseQuery(noteQueryOptions(noteId));
}

export function useNoteRename(campaignId: string, noteId: string) {
  return useRpcMutation(
    renameNote,
    (run, title: string) =>
      run({ identity: noteId, input: { title }, fields: ["title"] }),
    {
      fallback: "Could not rename the note.",
      // Refetching the note would hand the open editor an older body revision.
      onSuccess: ({ title }, queryClient) =>
        queryClient.setQueryData(
          noteQueryOptions(noteId).queryKey,
          note => note && { ...note, title }
        ),
      invalidate: [notesKey(campaignId)],
    }
  );
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
