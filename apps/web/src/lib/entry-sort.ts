// The orders of the World list. The API validates the same names. The first is the default.
export const ENTRY_SORTS = [
  "last_mentioned",
  "name",
  "last_edited",
  "last_created",
] as const;
export type EntrySort = (typeof ENTRY_SORTS)[number];

export const DEFAULT_ENTRY_SORT: EntrySort = "last_mentioned";

export const ENTRY_SORT_LABELS: Record<EntrySort, string> = {
  last_mentioned: "Latest session mention",
  name: "Name (A–Z)",
  last_edited: "Last edited",
  last_created: "Last created",
};

export const isEntrySort = (sort: unknown): sort is EntrySort =>
  typeof sort === "string" && (ENTRY_SORTS as readonly string[]).includes(sort);

/**
 * The sort of a URL value. Anything unknown gives the default. A parent route with no
 * `validateSearch` merges the raw value back into the search, so read the sort through this.
 */
export const entrySortOf = (sort: unknown): EntrySort =>
  isEntrySort(sort) ? sort : DEFAULT_ENTRY_SORT;
