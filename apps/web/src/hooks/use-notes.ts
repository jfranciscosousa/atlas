import { useSuspenseQuery, type QueryClient } from "@tanstack/react-query";
import {
  archiveNote,
  createNote,
  getNote,
  hideNote,
  listNotes,
  renameNote,
  restoreNote,
  revealNote,
} from "@atlas/api-client";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

// Matches the active and the archived list of one campaign.
const notesKey = (campaignId: string) =>
  rpcKey(listNotes, { input: { campaignId } });

export function notesQueryOptions(campaignId: string, archived = false) {
  return rpcQuery(
    listNotes,
    run =>
      run({
        input: { campaignId, archived },
        fields: ["id", "title", "revealed", "isOwner", "ownerName"],
      }),
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

// Set the open note directly: a refetch would hand its editor an older body revision.
const revealOptions = (campaignId: string) => ({
  fallback: "Could not update the note.",
  onSuccess: (
    { id, revealed }: { id: string; revealed: boolean },
    queryClient: QueryClient
  ) =>
    queryClient.setQueryData(
      noteQueryOptions(id).queryKey,
      note => note && { ...note, revealed }
    ),
  invalidate: [notesKey(campaignId)],
});

/** Reveals a note to the players. The list and the open note follow. */
export function useNoteReveal(campaignId: string) {
  return useRpcMutation(
    revealNote,
    (run, id: string) => run({ identity: id, fields: ["id", "revealed"] }),
    revealOptions(campaignId)
  );
}

export function useNoteHide(campaignId: string) {
  return useRpcMutation(
    hideNote,
    (run, id: string) => run({ identity: id, fields: ["id", "revealed"] }),
    revealOptions(campaignId)
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
        fields: [
          "id",
          "campaignId",
          "title",
          "bodyJson",

          "revealed",
          "isOwner",
          "ownerName",
        ],
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
