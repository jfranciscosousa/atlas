import { EyeIcon, EyeOffIcon } from "lucide-react";

import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { useNoteHide, useNoteReveal } from "../hooks/use-notes";

export function NoteVisibilityBadge({ revealed }: { revealed: boolean }) {
  return (
    <Badge
      variant={revealed ? "secondary" : "outline"}
      title={
        revealed
          ? "Every player in the campaign can read this note."
          : "Only its owner and the GM can read this note."
      }
    >
      {revealed ? "Revealed" : "Hidden"}
    </Badge>
  );
}

/** Reveals a hidden note to the players, or hides a revealed one. Owner and GM only. */
export function NoteRevealButton({
  campaignId,
  id,
  revealed,
  title,
  icon = false,
}: {
  campaignId: string;
  id: string;
  revealed: boolean;
  title: string;
  icon?: boolean;
}) {
  const revealNote = useNoteReveal(campaignId);
  const hideNote = useNoteHide(campaignId);
  const reveal = revealed ? hideNote : revealNote;
  const label = revealed ? "Hide from players" : "Reveal to players";
  const Icon = revealed ? EyeOffIcon : EyeIcon;

  return (
    <Button
      id={`note-${revealed ? "hide" : "reveal"}-${id}`}
      variant={icon ? "ghost" : "outline"}
      size={icon ? "icon" : "default"}
      aria-label={icon ? `${label}: ${title}` : undefined}
      title={label}
      disabled={reveal.isPending}
      onClick={() => reveal.mutate(id)}
    >
      <Icon aria-hidden="true" data-icon={icon ? undefined : "inline-start"} />
      {!icon && label}
    </Button>
  );
}
