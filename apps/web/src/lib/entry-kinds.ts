// The kinds of world entry, in display order. The API holds the statuses, the fields and the
// relations of each kind (`get_entry_kinds`); only the names that a page needs before that
// answer arrives are here: the navigation, the search results and the mention picker.
export const ENTRY_KINDS = [
  "npc",
  "location",
  "faction",
  "item",
  "creature",
  "plot",
] as const;
export type EntryKind = (typeof ENTRY_KINDS)[number];

export const ENTRY_KIND_LABELS: Record<
  EntryKind,
  { label: string; plural: string }
> = {
  npc: { label: "NPC", plural: "NPCs" },
  location: { label: "Location", plural: "Locations" },
  faction: { label: "Faction", plural: "Factions" },
  item: { label: "Item", plural: "Items" },
  creature: { label: "Creature", plural: "Creatures" },
  plot: { label: "Plot", plural: "Plots" },
};

export const isEntryKind = (kind: string): kind is EntryKind =>
  (ENTRY_KINDS as readonly string[]).includes(kind);

/** What `get_entry_kinds` returns for one kind. The action returns an untyped map. */
export type EntryKindSpec = {
  kind: EntryKind;
  label: string;
  plural: string;
  statuses: string[];
  default_status: string;
  fields: { key: string; label: string; max_length: number }[];
};

/** One relation, and the kinds that each end may have. */
export type RelationSpec = {
  relation: string;
  /** Reads from the first end to the second: "member of". */
  label: string;
  /** Reads from the second end back: "members". */
  inverse: string;
  from: string[];
  to: string[];
};

export type EntryKindsResponse = {
  kinds: EntryKindSpec[];
  relations: RelationSpec[];
};

/** A status as a person reads it: "missing" is "Missing". */
export const statusLabel = (status: string) =>
  status.charAt(0).toUpperCase() + status.slice(1);

/** A relation end is an entry or a character. */
export type RelationEnd = "character" | EntryKind;
export const endKindLabel = (kind: string) =>
  kind === "character"
    ? "Character"
    : (ENTRY_KIND_LABELS[kind as EntryKind]?.label ?? kind);

/** The page of an entry or a character. */
export function endPath(
  campaignId: string,
  kind: string,
  id: string,
  preview = false
) {
  const base = `/campaigns/${campaignId}`;
  if (kind === "character") return `${base}/characters/${id}`;
  return preview ? `${base}/preview/entries/${id}` : `${base}/entries/${id}`;
}
