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

export const KIND_ORDER: SearchKind[] = [
  "campaign",
  "session",
  "character",
  "note",
  "player_log",
];

export const KIND_LABELS: Record<SearchKind, string> = {
  campaign: "Campaigns",
  session: "Sessions",
  character: "Characters",
  note: "Notes",
  player_log: "Player logs",
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

/** Hits grouped by kind, in `KIND_ORDER`. The order inside a group is the rank of the API. */
export function groupHits(hits: SearchHit[]) {
  return KIND_ORDER.map(kind => ({
    kind,
    hits: hits.filter(hit => hit.kind === kind),
  })).filter(group => group.hits.length > 0);
}

// Same folding as the API: accents and case never matter.
const fold = (text: string) =>
  text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

const WORD = /[\p{L}\p{N}]+/gu;

export const queryTerms = (query: string) => [
  ...new Set(fold(query).match(WORD) ?? []),
];

/**
 * Splits `text` so that the words which contain a query term can be marked. The API also
 * accepts near matches; those words stay unmarked.
 */
export function highlight(text: string, terms: string[]) {
  const parts: { text: string; match: boolean }[] = [];
  let last = 0;
  for (const found of text.matchAll(WORD)) {
    const word = found[0];
    const start = found.index;
    const folded = fold(word);
    if (!terms.some(term => folded.includes(term))) continue;
    if (start > last)
      parts.push({ text: text.slice(last, start), match: false });
    parts.push({ text: word, match: true });
    last = start + word.length;
  }
  if (last < text.length) parts.push({ text: text.slice(last), match: false });
  return parts;
}
