import type { MentionKind } from "./blocknote-schema.ts";

import { sessionLabel } from "./session.ts";

export type MentionEntry = { kind: MentionKind; id: string; label: string };

export type MentionLabel =
  | { status: "found"; label: string }
  | { status: "restricted"; label: string }
  | { status: "deleted"; label: string };

/** What the lists of one campaign give: the entries the reader can read. */
export type MentionSources = {
  characters: { id: string; name: string | null }[];
  sessions: { id: string; number: number; title: string | null }[];
  notes: { id: string; title: string | null }[];
  archivedNotes: { id: string }[];
};

const key = (kind: MentionKind, id: string) => `${kind}:${id}`;

export function buildEntries(sources: MentionSources): MentionEntry[] {
  return [
    ...sources.characters.map(c => ({
      kind: "character" as const,
      id: c.id,
      label: c.name ?? "Unnamed character",
    })),
    ...sources.sessions.map(s => ({
      kind: "session" as const,
      id: s.id,
      label: sessionLabel(s),
    })),
    ...sources.notes.map(n => ({
      kind: "note" as const,
      id: n.id,
      label: n.title || "Untitled note",
    })),
  ];
}

/**
 * Names a mention for the reader. The document stores no name, so an entry the reader cannot
 * list is "Restricted entry", and an archived note is "Deleted entry".
 */
export function describeMention(
  entries: MentionEntry[],
  archivedNotes: { id: string }[],
  kind: MentionKind,
  id: string
): MentionLabel {
  const entry = entries.find(e => key(e.kind, e.id) === key(kind, id));
  if (entry) return { status: "found", label: entry.label };
  if (kind === "note" && archivedNotes.some(n => n.id === id))
    return { status: "deleted", label: "Deleted entry" };
  return { status: "restricted", label: "Restricted entry" };
}
