import { EyeIcon, EyeOffIcon } from "lucide-react";

import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { statusLabel } from "../lib/entry-kinds";
import { useEntryHidden } from "../hooks/use-entries";

export function EntryStatusBadge({ status }: { status: string }) {
  return <Badge variant="outline">{statusLabel(status)}</Badge>;
}

/** Only the GM sees a hidden entry, so a player never sees this badge. */
export function EntryHiddenBadge({ hidden }: { hidden: boolean }) {
  return hidden ? (
    <Badge
      variant="outline"
      title="Only you, the GM, can read this entry. Players do not see it."
    >
      <EyeOffIcon aria-hidden="true" data-icon="inline-start" />
      Hidden
    </Badge>
  ) : (
    <Badge variant="secondary" title="Players can read this entry.">
      Shown to players
    </Badge>
  );
}

/** The GM shows an entry to the players, or hides it again. */
export function EntryHiddenToggle({
  campaignId,
  entryId,
  hidden,
  name,
  icon = false,
}: {
  campaignId: string;
  entryId: string;
  hidden: boolean;
  name: string;
  icon?: boolean;
}) {
  const setHidden = useEntryHidden(campaignId, entryId);
  const label = hidden ? "Show to players" : "Hide from players";
  const Icon = hidden ? EyeIcon : EyeOffIcon;

  return (
    <Button
      id={`entry-hidden-${entryId}`}
      variant={icon ? "ghost" : "outline"}
      size={icon ? "icon" : "default"}
      aria-label={icon ? `${label}: ${name}` : undefined}
      title={label}
      disabled={setHidden.isPending}
      onClick={() => setHidden.mutate(!hidden)}
    >
      <Icon aria-hidden="true" data-icon={icon ? undefined : "inline-start"} />
      {!icon && label}
    </Button>
  );
}
