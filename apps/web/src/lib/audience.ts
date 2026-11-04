// Who reads a rich-text section. MCP gives the same audience next to the text, so an agent does
// not copy a secret into text that more people read. `Atlas.Audience` in the API is the source of
// these labels and rules; `Atlas.AudienceTest` fails when this file differs from it.
export type Audience =
  | "gm_only"
  | "only_me"
  | "me_and_gm"
  | "character"
  | "everyone";

export const AUDIENCE_LABELS: Record<Audience, string> = {
  gm_only: "GM only",
  only_me: "Private",
  me_and_gm: "Owner and GM",
  character: "Character",
  everyone: "Everyone",
};

export const AUDIENCE_HINTS: Record<Audience, string> = {
  gm_only: "Only the GM can read this.",
  only_me: "Only its owner can read this.",
  me_and_gm: "Only its owner and the GM can read this.",
  character:
    "Its owner, the GM, and the player of the linked character can read this.",
  everyone: "Every member of the campaign can read this.",
};

// The sections whose audience never changes, by "kind:section". A note body follows the visibility
// of the note. A world entry description follows its hidden flag: see `audienceOf`.
export const FIXED_AUDIENCE: Record<string, Audience> = {
  "campaign:description": "everyone",
  "campaign:progress_rewards": "everyone",
  "session:log": "everyone",
  "session:prep": "gm_only",
  "character:description": "everyone",
  "character:secret_notes": "gm_only",
  "player_log:body": "everyone",
  "skill:body": "only_me",
};

export type AudienceState = {
  hidden?: boolean;
  archivedAt?: string | null;
  visibility?: Exclude<Audience, "gm_only">;
};

/**
 * The audience of one section. `kind` is the name the server uses in a section reference: a
 * world entry names its own kind, such as "npc". A missing state gives the narrowest audience,
 * so a label never promises more readers than the text has.
 */
export function audienceOf(
  kind: string,
  section: string,
  state: AudienceState = {}
): Audience {
  const fixed = FIXED_AUDIENCE[`${kind}:${section}`];
  if (fixed) return fixed;
  if (kind === "note" && section === "body")
    return state.visibility ?? "only_me";
  if (section === "secret_notes") return "gm_only";
  if (section === "description")
    return state.hidden === false && !state.archivedAt ? "everyone" : "gm_only";
  return "only_me";
}
