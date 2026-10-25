// The kinds of world entry, in display order. The API validates the same names; these are
// needed before any answer arrives: the navigation, the search results and the mention picker.
// A kind is a label for grouping, not a schema.
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
