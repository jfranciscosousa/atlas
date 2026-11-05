import type { EntryKind } from "./entry-kinds.ts";
import type { MentionKind } from "./blocknote-schema.ts";

import { sessionLabel } from "./session.ts";

export type MentionEntry = {
  kind: MentionKind;
  id: string;
  label: string;
  /** An archived entry is out of the default lists, but a reader may still mention it. */
  archived?: boolean;
};

export type MentionLabel =
  | { status: "found"; label: string }
  | { status: "restricted"; label: string };

/** What the lists of one campaign give: the entries the reader can read. */
export type MentionSources = {
  characters: { id: string; name: string | null }[];
  sessions: { id: string; number: number; title: string | null }[];
  notes: { id: string; title: string | null }[];
  /** The world entries that the reader can list, hidden ones included when the reader is the GM. */
  entries: { id: string; kind: EntryKind; name: string }[];
  archivedNotes: { id: string; title: string | null }[];
  archivedEntries: { id: string; kind: EntryKind; name: string }[];
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
    ...sources.entries.map(e => ({ kind: e.kind, id: e.id, label: e.name })),
    ...sources.archivedNotes.map(n => ({
      kind: "note" as const,
      id: n.id,
      label: n.title || "Untitled note",
      archived: true,
    })),
    ...sources.archivedEntries.map(e => ({
      kind: e.kind,
      id: e.id,
      label: e.name,
      archived: true,
    })),
  ];
}

/**
 * Names a mention for the reader. The document stores no name, so an entry the reader cannot
 * list, archived ones included, is "Restricted entry".
 */
export function describeMention(
  entries: MentionEntry[],
  kind: MentionKind,
  id: string
): MentionLabel {
  const entry = entries.find(e => key(e.kind, e.id) === key(kind, id));
  if (entry) return { status: "found", label: entry.label };
  return { status: "restricted", label: "Restricted entry" };
}
