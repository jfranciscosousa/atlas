import { Link, useParams } from "@tanstack/react-router";

import type { MentionKind } from "../lib/blocknote-schema";

import { usePreview } from "../lib/preview";
import { isEntryKind } from "../lib/entry-kinds";
import { useMentionEntries } from "../hooks/use-mentions";

const CHIP =
  "rounded-md bg-primary/10 px-1 py-0.5 font-medium text-primary! no-underline!";

/** An inline @ link to a character, session, note or world entry. It shows the current name. */
export function MentionChip({ kind, id }: { kind: MentionKind; id: string }) {
  // Every page that holds an editor sits under one campaign.
  const { campaignId } = useParams({ strict: false });
  const { loading, describe } = useMentionEntries(campaignId);
  const mention = describe(kind, id);
  const preview = usePreview();

  if (loading)
    return (
      <span className={CHIP} aria-busy>
        @…
      </span>
    );
  if (mention.status !== "found" || !campaignId)
    return (
      <span className="rounded-md bg-muted px-1 py-0.5 text-muted-foreground italic">
        {mention.label}
      </span>
    );

  const text = `@${mention.label}`;
  const className = CHIP;
  // In Preview as player an entry opens as the player reads it.
  if (isEntryKind(kind))
    return preview ? (
      <Link
        to="/campaigns/$campaignId/preview/entries/$entryId"
        params={{ campaignId, entryId: id }}
        className={className}
      >
        {text}
      </Link>
    ) : (
      <Link
        to="/campaigns/$campaignId/entries/$entryId"
        params={{ campaignId, entryId: id }}
        className={className}
      >
        {text}
      </Link>
    );
  switch (kind) {
    case "character":
      return (
        <Link
          to="/campaigns/$campaignId/characters/$characterId"
          params={{ campaignId, characterId: id }}
          className={className}
        >
          {text}
        </Link>
      );
    case "session":
      return (
        <Link
          to="/campaigns/$campaignId/sessions/$sessionId"
          params={{ campaignId, sessionId: id }}
          className={className}
        >
          {text}
        </Link>
      );
    default:
      return (
        <Link
          to="/campaigns/$campaignId/notes/$noteId"
          params={{ campaignId, noteId: id }}
          className={className}
        >
          {text}
        </Link>
      );
  }
}

const PAGES = {
  character: "characters",
  session: "sessions",
  note: "notes",
} as const;

const pageOf = (kind: MentionKind) =>
  isEntryKind(kind) ? "entries" : PAGES[kind];

/** What a copy carries to other apps: a link with a full URL, since a relative one is dead there. */
export function MentionExternal({
  kind,
  id,
}: {
  kind: MentionKind;
  id: string;
}) {
  const { campaignId } = useParams({ strict: false });
  const mention = useMentionEntries(campaignId).describe(kind, id);
  if (mention.status !== "found" || !campaignId)
    return <span>{mention.label}</span>;

  return (
    <a
      href={`${window.location.origin}/campaigns/${campaignId}/${pageOf(kind)}/${id}`}
    >{`@${mention.label}`}</a>
  );
}
