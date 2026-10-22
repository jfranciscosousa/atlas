import { useQueries } from "@tanstack/react-query";

import type { MentionKind } from "../lib/blocknote-schema.ts";

import { sessionsQueryOptions } from "./use-sessions.ts";
import { notesQueryOptions } from "./use-notes.ts";
import { charactersQueryOptions } from "./use-characters.ts";
import { buildEntries, describeMention } from "../lib/mentions.ts";

/**
 * The entries of a campaign that a text can mention, from the lists the pages already load.
 * `loading` is true until all lists arrive, so a mention never flashes "Restricted entry".
 */
export function useMentionEntries(campaignId: string | undefined) {
  const id = campaignId ?? "";
  const [characters, sessions, notes, archived] = useQueries({
    queries: [
      { ...charactersQueryOptions(id), enabled: !!campaignId },
      { ...sessionsQueryOptions(id), enabled: !!campaignId },
      { ...notesQueryOptions(id), enabled: !!campaignId },
      { ...notesQueryOptions(id, true), enabled: !!campaignId },
    ],
  });
  const loading =
    !!campaignId &&
    [characters, sessions, notes, archived].some(q => q.isPending);
  const archivedNotes = archived.data ?? [];
  const entries = buildEntries({
    characters: characters.data ?? [],
    sessions: sessions.data ?? [],
    notes: notes.data ?? [],
    archivedNotes,
  });

  return {
    loading,
    entries,
    describe: (kind: MentionKind, mentionId: string) =>
      describeMention(entries, archivedNotes, kind, mentionId),
  };
}
