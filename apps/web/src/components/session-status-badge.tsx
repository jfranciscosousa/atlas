import { Badge } from "./ui/badge";

export type SessionStatus = "in_prep" | "done";

export function SessionStatusBadge({ status }: { status: SessionStatus }) {
  return (
    <Badge
      variant={status === "done" ? "secondary" : "outline"}
      title={
        status === "done"
          ? "The GM played this session."
          : "The GM has not played this session yet."
      }
    >
      {status === "done" ? "Done" : "In prep"}
    </Badge>
  );
}
