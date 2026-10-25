import { useQueries } from "@tanstack/react-query";

import type { MentionKind } from "../lib/blocknote-schema.ts";

import { sessionsQueryOptions } from "./use-sessions.ts";
import { notesQueryOptions } from "./use-notes.ts";
import { entriesQueryOptions } from "./use-entries.ts";
import { charactersQueryOptions } from "./use-characters.ts";
import { usePreview } from "../lib/preview.ts";
import {
  archivedEntries,
  buildEntries,
  describeMention,
} from "../lib/mentions.ts";

/**
 * The entries of a campaign that a text can mention, from the lists the pages already load.
 * `loading` is true until all lists arrive, so a mention never flashes "Restricted entry".
 * Preview as player lists only the world entries that a player reads.
 */
export function useMentionEntries(campaignId: string | undefined) {
  const id = campaignId ?? "";
  const asPlayer = usePreview();
  const [characters, sessions, notes, archived, entries, archivedWorld] =
    useQueries({
      queries: [
        { ...charactersQueryOptions(id), enabled: !!campaignId },
        { ...sessionsQueryOptions(id), enabled: !!campaignId },
        { ...notesQueryOptions(id), enabled: !!campaignId },
        { ...notesQueryOptions(id, true), enabled: !!campaignId },
        { ...entriesQueryOptions(id, { asPlayer }), enabled: !!campaignId },
        {
          ...entriesQueryOptions(id, { archived: true, asPlayer }),
          enabled: !!campaignId,
        },
      ],
    });
  const loading =
    !!campaignId &&
    [characters, sessions, notes, archived, entries, archivedWorld].some(
      q => q.isPending
    );
  const sources = {
    characters: characters.data ?? [],
    sessions: sessions.data ?? [],
    notes: notes.data ?? [],
    entries: (entries.data ?? []).map(({ id, kind, name }) => ({
      id,
      kind,
      name,
    })),
    archivedNotes: archived.data ?? [],
    archivedEntries: (archivedWorld.data ?? []).map(({ id, kind }) => ({
      id,
      kind,
    })),
  };
  const built = buildEntries(sources);
  const archivedList = archivedEntries(sources);

  return {
    loading,
    entries: built,
    describe: (kind: MentionKind, mentionId: string) =>
      describeMention(built, archivedList, kind, mentionId),
  };
}
