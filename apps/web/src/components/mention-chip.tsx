import { Link, useParams } from "@tanstack/react-router";

import type { MentionKind } from "../lib/blocknote-schema";

import { useMentionEntries } from "../hooks/use-mentions";

const CHIP =
  "rounded-md bg-primary/10 px-1 py-0.5 font-medium text-primary! no-underline!";

/** An inline @ link to a character, session or note. It shows the current name. */
export function MentionChip({ kind, id }: { kind: MentionKind; id: string }) {
  // Every page that holds an editor sits under one campaign.
  const { campaignId } = useParams({ strict: false });
  const { loading, describe } = useMentionEntries(campaignId);
  const mention = describe(kind, id);

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
    case "note":
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
