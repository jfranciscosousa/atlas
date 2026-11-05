import { Badge } from "./ui/badge";

export type CharacterStatus = "active" | "retired" | "dead";

export const CHARACTER_STATUS_LABELS: Record<CharacterStatus, string> = {
  active: "Active",
  retired: "Retired",
  dead: "Dead",
};

// An active character needs no badge: it is the normal case.
export function CharacterStatusBadge({ status }: { status: CharacterStatus }) {
  if (status === "active") return null;
  return <Badge variant="secondary">{CHARACTER_STATUS_LABELS[status]}</Badge>;
}
