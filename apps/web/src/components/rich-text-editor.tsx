import { useEffect, useMemo, useRef, useState } from "react";
import { cn } from "cn";
import { useBlocker } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { BlockNoteView } from "@blocknote/shadcn";
import {
  FilePanel,
  FilePanelController,
  UploadTab,
  useCreateBlockNote,
  type FilePanelProps,
} from "@blocknote/react";

import type { BlockNoteDocument } from "../lib/blocknote-schema";
import "@blocknote/shadcn/style.css";

import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { createImageResolver, uploadImage } from "../lib/images";
import { schema } from "../lib/blocknote-schema";
import { createAutosaver, type SaveState } from "../lib/autosave";
import {
  saveSessionDocument,
  type SessionSection,
} from "../hooks/use-sessions";
import { savePlayerLogDocument } from "../hooks/use-player-logs";
import { saveNoteDocument } from "../hooks/use-notes";
import {
  fetchImageUrl,
  saveCampaignSection,
  type Section,
} from "../hooks/use-campaigns";

// Documents hold only uploaded images, so the panel offers no "Embed" tab for external URLs.
function UploadOnlyFilePanel(props: FilePanelProps) {
  const [, setLoading] = useState(false);
  return (
    <FilePanel
      {...props}
      tabs={[
        {
          name: "Upload",
          tabPanel: <UploadTab {...props} setLoading={setLoading} />,
        },
      ]}
    />
  );
}

type Props = {
  // The campaign, note, or session that owns this section. It decides where a save goes.
  parent: { kind: "campaign" | "note" | "session" | "playerLog"; id: string };
  section: Section | "body" | SessionSection;
  // Page elements get this ID prefix. Set it when one page holds several editors of a section.
  id?: string;
  label: string;
  hint?: string;
  // The label stays for screen readers. Use it when a tab already shows the name.
  hideLabel?: boolean;
  initial: BlockNoteDocument;
  revision: number;
  readOnly?: boolean;
};

export default function RichTextEditor({
  parent,
  section,
  id = section,
  label,
  hint,
  hideLabel = false,
  initial,
  revision,
  readOnly = false,
}: Props) {
  const queryClient = useQueryClient();
  const [state, setState] = useState<SaveState>({ status: "idle" });
  // The blocker reads the latest state outside React's render cycle.
  const stateRef = useRef(state);
  const report = (next: SaveState) => {
    stateRef.current = next;
    setState(next);
  };
  const meta = () => queryClient.getDefaultOptions().mutations?.meta;

  const resolveFileUrl = useMemo(
    () =>
      createImageResolver({
        fetchUrl: id =>
          fetchImageUrl(queryClient.getDefaultOptions().mutations?.meta, id),
      }),
    [queryClient]
  );

  const editor = useCreateBlockNote({
    schema,
    // The server owns validation. A document saved earlier is always one this schema accepts.
    initialContent: initial.length
      ? (initial as unknown as NonNullable<
          Parameters<typeof useCreateBlockNote>[0]
        >["initialContent"])
      : undefined,
    uploadFile: file => uploadImage({ file, csrfToken: meta()?.csrfToken }),
    resolveFileUrl,
  });

  const autosaver =
    useRef<ReturnType<typeof createAutosaver<BlockNoteDocument>>>(null);

  // Leaving waits for a pending save. A failed save asks before the edits are dropped.
  useBlocker({
    shouldBlockFn: async () => {
      if (stateRef.current.status === "saving")
        await autosaver.current?.flush();
      return (
        stateRef.current.status === "error" &&
        !window.confirm("Your latest edits are not saved. Leave anyway?")
      );
    },
    enableBeforeUnload: () =>
      stateRef.current.status === "saving" ||
      stateRef.current.status === "error",
  });
  useEffect(() => {
    if (readOnly) return;
    const saver = createAutosaver<BlockNoteDocument>({
      revision,
      onState: report,
      save: (doc, expected) => {
        const meta = queryClient.getDefaultOptions().mutations?.meta;
        if (parent.kind === "session")
          return saveSessionDocument(
            meta,
            parent.id,
            section as SessionSection,
            doc,
            expected
          );
        if (parent.kind === "playerLog")
          return savePlayerLogDocument(meta, parent.id, doc, expected);
        if (parent.kind === "note")
          return saveNoteDocument(meta, parent.id, doc, expected);
        return saveCampaignSection(
          meta,
          parent.id,
          section as Section,
          doc,
          expected
        );
      },
    });
    autosaver.current = saver;
    const flush = () => void saver.flush();
    document.addEventListener("visibilitychange", flush);
    return () => {
      document.removeEventListener("visibilitychange", flush);
      void saver.flush();
      saver.dispose();
    };
  }, [queryClient, parent.kind, parent.id, section, revision, readOnly]);

  return (
    <section id={`${id}-section`} aria-labelledby={`${id}-heading`}>
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2
            id={`${id}-heading`}
            className={cn(
              "font-heading text-xl font-semibold tracking-tight",
              hideLabel && "sr-only"
            )}
          >
            {label}
          </h2>
          {hint && (
            <p className="mt-0.5 text-sm text-muted-foreground">{hint}</p>
          )}
        </div>
        <span
          id={`${id}-status`}
          role="status"
          aria-live="polite"
          className="text-xs text-muted-foreground"
        >
          {state.status === "saving" && "Saving…"}
          {state.status === "saved" && "Saved"}
        </span>
      </div>
      <div
        id={`${id}-editor`}
        className="mt-4 min-h-48 rounded-2xl border bg-card py-4 shadow-xs transition-shadow focus-within:shadow-md [&_.bn-editor]:min-h-36"
      >
        <BlockNoteView
          editor={editor}
          theme="light"
          editable={!readOnly}
          filePanel={false}
          onChange={() =>
            autosaver.current?.change(
              editor.document as unknown as BlockNoteDocument
            )
          }
        >
          <FilePanelController filePanel={UploadOnlyFilePanel} />
        </BlockNoteView>
      </div>
      {state.status === "error" && (
        <Alert id={`${id}-error`} variant="destructive" className="mt-3">
          <AlertDescription>{state.message}</AlertDescription>
          {state.kind === "stale" ? (
            <Button variant="outline" onClick={() => window.location.reload()}>
              Reload
            </Button>
          ) : (
            <Button
              id={`${id}-retry`}
              variant="outline"
              onClick={() => void autosaver.current?.retry()}
            >
              Retry
            </Button>
          )}
        </Alert>
      )}
    </section>
  );
}
