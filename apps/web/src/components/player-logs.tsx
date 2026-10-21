import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { getEditor } from "./rich-text-editor-loader";
import { usePlayerLogCreate, usePlayerLogs } from "../hooks/use-player-logs";

/** Every player's recollection of a session. Each player edits their own. The GM only reads. */
export function PlayerLogs({
  sessionId,
  isGm,
}: {
  sessionId: string;
  isGm: boolean;
}) {
  const RichTextEditor = getEditor();
  const logs = usePlayerLogs(sessionId).data;
  const create = usePlayerLogCreate(sessionId);
  const hasMine = logs.some(log => log.isMine);
  // Your own log comes first.
  const sorted = [...logs].sort((a, b) => Number(b.isMine) - Number(a.isMine));

  return (
    <div className="space-y-8">
      {!isGm && !hasMine && (
        <div className="flex flex-col items-start gap-3 rounded-2xl border bg-card p-6">
          <p className="text-sm text-muted-foreground">
            Write what your character saw and did. Every player and the GM can
            read it.
          </p>
          <Button
            id="player-log-start"
            disabled={create.isPending}
            onClick={() => create.mutate()}
          >
            Write your log
          </Button>
          {create.error && (
            <Alert variant="destructive">
              <AlertDescription>{create.error.message}</AlertDescription>
            </Alert>
          )}
        </div>
      )}
      {logs.length === 0 && (isGm || hasMine) && (
        <p id="player-logs-empty" className="text-sm text-muted-foreground">
          No player has written a log yet.
        </p>
      )}
      {sorted.map(log => (
        <RichTextEditor
          // BlockNote reads its content once. A log of someone else reloads when its revision changes.
          key={log.isMine ? log.id : `${log.id}-${log.bodyRevision}`}
          id={`player-log-${log.id}`}
          parent={{ kind: "playerLog", id: log.id }}
          section="body"
          label={log.isMine ? "Your log" : (log.authorName ?? "A player")}
          initial={log.bodyJson}
          revision={log.bodyRevision}
          readOnly={!log.isMine}
        />
      ))}
    </div>
  );
}
