export type SearchKind =
  | "campaign"
  | "session"
  | "character"
  | "note"
  | "player_log";

/** One hit of the `search` action. The action returns an untyped map, so the keys stay snake_case. */
export type SearchHit = {
  kind: SearchKind;
  id: string;
  title: string;
  campaign_id: string;
  campaign_name: string;
  /** Set on player logs only: a log opens on the page of its session. */
  session_id: string | null;
  sections: { section: string; blocks: { id: string; text: string }[] }[];
};

export type SearchResponse = { hits: SearchHit[]; more: boolean };

export const KIND_NAMES: Record<SearchKind, string> = {
  campaign: "Campaign",
  session: "Session",
  character: "Character",
  note: "Note",
  player_log: "Player log",
};

const SECTION_LABELS: Record<string, string> = {
  description: "Description",
  progress_rewards: "Progress and rewards",
  secret_notes: "Secret notes",
  log: "Log",
  prep: "Prep",
  body: "Text",
};

export function sectionLabel(section: string) {
  return SECTION_LABELS[section] ?? section;
}

/** The page that shows a hit. */
export function hitPath(
  hit: Pick<SearchHit, "kind" | "id" | "campaign_id" | "session_id">
) {
  const base = `/campaigns/${hit.campaign_id}`;
  switch (hit.kind) {
    case "campaign":
      return base;
    case "session":
      return `${base}/sessions/${hit.id}`;
    case "player_log":
      return `${base}/sessions/${hit.session_id ?? ""}`;
    case "character":
      return `${base}/characters/${hit.id}`;
    case "note":
      return `${base}/notes/${hit.id}`;
  }
}

// Same folding as the API: accents and case never matter.
const fold = (text: string) =>
  text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

// A chunk is letters and digits that punctuation joins without a space: M.A.77, in-world.
const CHUNK = /[\p{L}\p{N}]+(?:[^\s\p{L}\p{N}]+[\p{L}\p{N}]+)*/gu;
const WORD = /[\p{L}\p{N}]+/gu;

// Same rule as the API: a chunk is one word with its punctuation removed.
const joined = (chunk: string) => (fold(chunk).match(WORD) ?? []).join("");

export const queryTerms = (query: string) => [
  ...new Set((fold(query).match(CHUNK) ?? []).map(joined)),
];

/**
 * Splits `text` so that the chunks which contain a query term can be marked. The API also
 * accepts near matches; those chunks stay unmarked.
 */
export function highlight(source: string, terms: string[]) {
  // Composed letters only: a loose accent mark would split its chunk.
  const text = source.normalize("NFC");
  const parts: { text: string; match: boolean }[] = [];
  let last = 0;
  for (const found of text.matchAll(CHUNK)) {
    const chunk = found[0];
    const start = found.index;
    const word = joined(chunk);
    if (!terms.some(term => word.includes(term))) continue;
    if (start > last)
      parts.push({ text: text.slice(last, start), match: false });
    parts.push({ text: chunk, match: true });
    last = start + chunk.length;
  }
  if (last < text.length) parts.push({ text: text.slice(last), match: false });
  return parts;
}
