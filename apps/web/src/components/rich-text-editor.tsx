import { useEffect, useMemo, useRef, useState } from "react";
import { cn } from "cn";
import { useBlocker, useParams } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { BlockNoteView } from "@blocknote/shadcn";
import {
  FilePanel,
  FilePanelController,
  SuggestionMenuController,
  UploadTab,
  useCreateBlockNote,
  type FilePanelProps,
} from "@blocknote/react";
import { withCollaboration } from "@blocknote/core/yjs";
import { filterSuggestionItems } from "@blocknote/core";

import type { SaveState } from "../lib/save-tracker";
import type { SessionSection } from "../hooks/use-sessions";
import "@blocknote/shadcn/style.css";

import type { CharacterSection } from "../hooks/use-characters";

import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { summarize, type Person } from "../lib/presence";
import { createImageResolver, uploadImage } from "../lib/images";
import { schema } from "../lib/editor-schema";
import {
  FRAGMENT,
  openDocument,
  type Collab,
  type CollabNotice,
  type CollabStatus,
} from "../lib/collab";
import {
  mentionsToAtlasLinks,
  type BlockNoteDocument,
} from "../lib/blocknote-schema";
import { useMentionEntries } from "../hooks/use-mentions";
import { fetchImageUrl, type Section } from "../hooks/use-campaigns";

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
  parent: {
    kind: "campaign" | "note" | "session" | "playerLog" | "character";
    id: string;
  };
  section: Section | "body" | SessionSection | CharacterSection;
  // Page elements get this ID prefix. Set it when one page holds several editors of a section.
  id?: string;
  label: string;
  hint?: string;
  // The label stays for screen readers. Use it when a tab already shows the name.
  hideLabel?: boolean;
  // The text as last saved. It shows while the live connection starts.
  initial: BlockNoteDocument;
  // The editor stays read-only, whatever the server allows.
  readOnly?: boolean;
  // Gives the caller a way to replace the whole text from Markdown, while the editor is live and
  // writable. The change goes through live editing like a typed one. Pass a stable function.
  onReplace?: (
    replace: ((markdown: string) => Promise<void>) | undefined
  ) => void;
};

// The server names a section `kind:id:section`.
const KINDS = {
  campaign: "campaign",
  note: "note",
  session: "session",
  playerLog: "player_log",
  character: "character",
} as const;

const MENTION_GROUPS = {
  character: "Characters",
  session: "Sessions",
  note: "Notes",
} as const;

const NOTICES: Record<CollabNotice["kind"], string> = {
  revoked: "You no longer have access to this text.",
  unavailable: "This text could not be opened. Reload to try again.",
  reset: "This text was replaced by another change. Reload to see it.",
  rejected: "The server did not accept your last change.",
};

const SAVE_TEXT: Partial<Record<SaveState, string>> = {
  saving: "Saving…",
  saved: "Saved",
  failed: "Not saved. Reload and try again.",
};

export default function RichTextEditor({
  parent,
  section,
  id = section,
  label,
  hint,
  hideLabel = false,
  initial,
  readOnly = false,
  onReplace,
}: Props) {
  const queryClient = useQueryClient();
  const { campaignId } = useParams({ strict: false });
  const { entries: mentionable } = useMentionEntries(campaignId);
  const meta = () => queryClient.getDefaultOptions().mutations?.meta;
  const ref = `${KINDS[parent.kind]}:${parent.id}:${section}`;

  const [collab, setCollab] = useState<Collab>();
  const [status, setStatus] = useState<CollabStatus>("connecting");
  const [canWrite, setCanWrite] = useState(false);
  const [notice, setNotice] = useState<CollabNotice>();
  const [save, setSave] = useState<SaveState>("idle");
  const [people, setPeople] = useState<Person[]>([]);
  // Once the first sync is done the live document replaces the saved text for good.
  const [live, setLive] = useState(false);
  // The blocker reads the latest value outside React's render cycle.
  const collabRef = useRef<Collab>(undefined);
  const uploadsRef = useRef(0);
  const previewsRef = useRef<string[]>([]);

  useEffect(() => {
    const opened = openDocument(ref, meta()?.csrfToken ?? "", {
      onStatus: next => {
        setStatus(next);
        if (next === "synced") setLive(true);
      },
      onPermissions: setCanWrite,
      onNotice: setNotice,
      onSaveState: setSave,
      onPresence: setPeople,
    });
    collabRef.current = opened;
    setCollab(opened);
    return () => {
      opened.destroy();
      collabRef.current = undefined;
      setCollab(undefined);
      setStatus("connecting");
      setLive(false);
      setNotice(undefined);
      setSave("idle");
      setPeople([]);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the CSRF token does not change the document
  }, [ref]);

  const resolveFileUrl = useMemo(
    () =>
      createImageResolver({
        fetchUrl: id =>
          fetchImageUrl(queryClient.getDefaultOptions().mutations?.meta, id),
      }),
    [queryClient]
  );

  // A primed preview stays valid until the editor closes.
  useEffect(
    () => () => previewsRef.current.forEach(url => URL.revokeObjectURL(url)),
    []
  );

  const common = {
    schema,
    uploadFile: async (file: File, blockId?: string) => {
      uploadsRef.current++;
      // The block holds no URL until the upload ends, so the preview lives only in the DOM.
      const preview = URL.createObjectURL(file);
      const loading = document.querySelector(
        `[data-id="${blockId}"] .bn-file-loading-preview`
      );
      if (loading) {
        const image = document.createElement("img");
        image.src = preview;
        image.className = "bn-visual-media";
        image.style.opacity = "0.5";
        loading.replaceChildren(image);
      }
      previewsRef.current.push(preview);
      try {
        const reference = await uploadImage({
          file,
          csrfToken: meta()?.csrfToken,
        });
        // The block then shows the local image at once, without a second load from the server.
        resolveFileUrl.prime(reference, preview);
        return reference;
      } finally {
        uploadsRef.current--;
      }
    },
    resolveFileUrl,
    pasteHandler: ({
      event,
      editor,
      defaultPasteHandler,
    }: {
      event: ClipboardEvent;
      editor: { pasteHTML: (html: string, raw?: boolean) => void };
      defaultPasteHandler: () => boolean | undefined;
    }) => {
      const html = event.clipboardData?.getData("blocknote/html");
      if (!html) return defaultPasteHandler();
      editor.pasteHTML(mentionsToAtlasLinks(html), true);
      return true;
    },
  };
  const editor = useCreateBlockNote(
    live && collab
      ? withCollaboration({
          ...common,
          collaboration: {
            provider: collab.provider,
            fragment: collab.doc.getXmlFragment(FRAGMENT),
            // The server ignores this and sets the name and colour itself.
            user: { name: "You", color: "#6b7280" },
          },
        })
      : {
          ...common,
          // The server owns validation. A saved document is always one this schema accepts.
          initialContent: initial.length
            ? (initial as unknown as NonNullable<
                Parameters<typeof useCreateBlockNote>[0]
              >["initialContent"])
            : undefined,
        },
    [live, collab]
  );

  // After access ended or the text was replaced, the old text must not stay on screen.
  const closed =
    notice?.kind === "revoked" ||
    notice?.kind === "reset" ||
    notice?.kind === "unavailable";

  const writing = canWrite && !readOnly;
  const statusText = notice
    ? undefined
    : !live
      ? "Connecting…"
      : status === "offline"
        ? writing && save === "unsaved-offline"
          ? "Reconnecting… your edits are not saved yet"
          : "Reconnecting…"
        : writing
          ? SAVE_TEXT[save]
          : undefined;

  const { shown, more } = summarize(people);

  useEffect(() => {
    if (!onReplace || !live || !writing) return;
    onReplace(async markdown => {
      editor.replaceBlocks(
        editor.document,
        await editor.tryParseMarkdownToBlocks(markdown)
      );
    });
    return () => onReplace(undefined);
  }, [onReplace, editor, live, writing]);

  // Leaving with edits that never reached the server, or an image still uploading, asks first.
  const unsaved = () =>
    !!collabRef.current?.hasUnsyncedEdits() || uploadsRef.current > 0;
  useBlocker({
    shouldBlockFn: () =>
      unsaved() &&
      !window.confirm("Your latest edits are not saved. Leave anyway?"),
    enableBeforeUnload: unsaved,
  });

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
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          {!notice && people.length > 0 && (
            <span id={`${id}-presence`}>
              Also here:{" "}
              {shown.map((person, index) => (
                <span key={person.key} className="whitespace-nowrap">
                  <span
                    aria-hidden
                    className="mr-1 inline-block size-2 rounded-full"
                    style={{ backgroundColor: person.color }}
                  />
                  {person.name}
                  {index < shown.length - 1 && ", "}
                </span>
              ))}
              {more > 0 && ` and ${more} more`}
            </span>
          )}
          <span id={`${id}-status`} role="status" aria-live="polite">
            {statusText}
          </span>
        </div>
      </div>
      {!closed && (
        <div
          id={`${id}-editor`}
          // The saved text is replaced by the live editor, which rebuilds every chip. A click that
          // starts on an old chip and ends on a new one does nothing, so the old text takes no clicks.
          className={cn(
            "mt-4 min-h-48 rounded-2xl border bg-card py-4 shadow-xs transition-shadow focus-within:shadow-md [&_.bn-editor]:min-h-36",
            !live && "pointer-events-none"
          )}
        >
          <BlockNoteView
            editor={editor}
            theme="light"
            editable={live && canWrite && !readOnly && !notice}
            filePanel={false}
          >
            <FilePanelController filePanel={UploadOnlyFilePanel} />
            <SuggestionMenuController
              triggerCharacter="@"
              getItems={async query =>
                filterSuggestionItems(
                  mentionable.map(entry => ({
                    title: entry.label,
                    group: MENTION_GROUPS[entry.kind],
                    onItemClick: () =>
                      editor.insertInlineContent([
                        {
                          type: "mention",
                          props: { kind: entry.kind, id: entry.id },
                        },
                        " ",
                      ]),
                  })),
                  query
                )
              }
            />
          </BlockNoteView>
        </div>
      )}
      {notice && (
        <Alert id={`${id}-error`} variant="destructive" className="mt-3">
          <AlertDescription>
            {NOTICES[notice.kind]}
            {notice.kind === "rejected" && ` ${notice.reason}`}
          </AlertDescription>
          {notice.kind !== "revoked" && (
            <Button variant="outline" onClick={() => window.location.reload()}>
              Reload
            </Button>
          )}
        </Alert>
      )}
    </section>
  );
}
