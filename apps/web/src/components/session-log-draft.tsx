import { useState } from "react";
import { SparklesIcon, TriangleAlertIcon } from "lucide-react";

import { Spinner } from "./ui/spinner";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Alert, AlertDescription, AlertTitle } from "./ui/alert";
import { useSessionDraftLog } from "../hooks/use-sessions";

/**
 * Asks the server for a new final log, built from the log and the player logs. The GM reads the
 * draft and accepts it. Accepting replaces the log. The log editor's history can bring it back.
 */
export function SessionLogDraft({
  sessionId,
  replaceLog,
}: {
  sessionId: string;
  // Set while the log editor is live and writable.
  replaceLog: ((markdown: string) => Promise<void>) | undefined;
}) {
  const [open, setOpen] = useState(false);
  const draft = useSessionDraftLog(sessionId);

  return (
    <>
      <Button
        id="session-draft-log"
        variant="outline"
        disabled={!replaceLog}
        onClick={() => {
          setOpen(true);
          draft.mutate();
        }}
      >
        <SparklesIcon aria-hidden="true" data-icon="inline-start" />
        Draft log with AI
      </Button>
      <Dialog
        open={open}
        onOpenChange={next => {
          setOpen(next);
          if (!next) draft.reset();
        }}
      >
        <DialogContent className="sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Draft of the final log</DialogTitle>
            <DialogDescription>
              Written by AI from your log and the player logs. It never reads
              your prep. Accepting replaces the current log.
            </DialogDescription>
          </DialogHeader>
          {draft.isPending && (
            <p
              id="session-draft-pending"
              className="flex items-center gap-2 text-sm text-muted-foreground"
            >
              <Spinner /> Reading the logs…
            </p>
          )}
          {draft.error && (
            <Alert id="session-draft-error" variant="destructive">
              <AlertDescription>{draft.error.message}</AlertDescription>
            </Alert>
          )}
          {draft.data && draft.data.conflicts.length > 0 && (
            <Alert id="session-draft-conflicts">
              <TriangleAlertIcon aria-hidden="true" />
              <AlertTitle>The logs contradict each other</AlertTitle>
              <AlertDescription>
                <ul className="list-disc space-y-1 pl-4">
                  {draft.data.conflicts.map(conflict => (
                    <li key={conflict}>{conflict}</li>
                  ))}
                </ul>
              </AlertDescription>
            </Alert>
          )}
          {draft.data && (
            <pre
              id="session-draft-text"
              className="max-h-[50vh] overflow-y-auto rounded-xl border bg-muted/40 p-4 font-sans text-sm whitespace-pre-wrap"
            >
              {draft.data.draft}
            </pre>
          )}
          <DialogFooter>
            <Button
              variant="outline"
              disabled={draft.isPending}
              onClick={() => draft.mutate()}
            >
              Try again
            </Button>
            <Button
              id="session-draft-accept"
              disabled={!draft.data || !replaceLog}
              onClick={() => {
                if (!draft.data || !replaceLog) return;
                void replaceLog(draft.data.draft).then(() => setOpen(false));
              }}
            >
              Replace the log
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
