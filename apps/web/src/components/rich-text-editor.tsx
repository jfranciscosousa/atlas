import { useEffect, useMemo, useRef, useState } from "react";
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
  campaignId: string;
  section: Section;
  label: string;
  initial: BlockNoteDocument;
  revision: number;
};

export default function RichTextEditor({
  campaignId,
  section,
  label,
  initial,
  revision,
}: Props) {
  const queryClient = useQueryClient();
  const [state, setState] = useState<SaveState>({ status: "idle" });
  const meta = () => queryClient.getDefaultOptions().mutations?.meta;

  const resolveFileUrl = useMemo(
    () =>
      createImageResolver({
        fetchUrl: id =>
          fetchImageUrl(
            queryClient.getDefaultOptions().mutations?.meta,
            campaignId,
            section,
            id
          ),
      }),
    [queryClient, campaignId, section]
  );

  const editor = useCreateBlockNote({
    schema,
    // The server owns validation. A document saved earlier is always one this schema accepts.
    initialContent: initial.length
      ? (initial as unknown as NonNullable<
          Parameters<typeof useCreateBlockNote>[0]
        >["initialContent"])
      : undefined,
    uploadFile: file =>
      uploadImage({
        campaignId,
        section,
        file,
        csrfToken: meta()?.csrfToken,
      }),
    resolveFileUrl,
  });

  const autosaver =
    useRef<ReturnType<typeof createAutosaver<BlockNoteDocument>>>(null);
  useEffect(() => {
    const saver = createAutosaver<BlockNoteDocument>({
      revision,
      onState: setState,
      save: (doc, expected) =>
        saveCampaignSection(
          queryClient.getDefaultOptions().mutations?.meta,
          campaignId,
          section,
          doc,
          expected
        ),
    });
    autosaver.current = saver;
    const flush = () => void saver.flush();
    document.addEventListener("visibilitychange", flush);
    return () => {
      document.removeEventListener("visibilitychange", flush);
      void saver.flush();
      saver.dispose();
    };
  }, [queryClient, campaignId, section, revision]);

  return (
    <section
      id={`${section}-section`}
      aria-labelledby={`${section}-heading`}
      className="mt-8"
    >
      <div className="flex items-center justify-between gap-3">
        <h2 id={`${section}-heading`} className="text-lg font-semibold">
          {label}
        </h2>
        <span
          id={`${section}-status`}
          role="status"
          aria-live="polite"
          className="text-xs text-muted-foreground"
        >
          {state.status === "saving" && "Saving…"}
          {state.status === "saved" && "Saved"}
        </span>
      </div>
      <div
        id={`${section}-editor`}
        className="mt-3 min-h-40 rounded-lg border border-border py-2"
      >
        <BlockNoteView
          editor={editor}
          theme="light"
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
        <Alert id={`${section}-error`} variant="destructive" className="mt-3">
          <AlertDescription>{state.message}</AlertDescription>
          {state.kind === "stale" ? (
            <Button variant="outline" onClick={() => window.location.reload()}>
              Reload
            </Button>
          ) : (
            <Button
              id={`${section}-retry`}
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
