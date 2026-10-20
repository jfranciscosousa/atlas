import { useState } from "react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { noteQueryOptions, useNote, useNoteRename } from "../hooks/use-notes";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import { Input } from "../components/ui/input";
import { buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { getEditor, loadEditor } from "../components/rich-text-editor-loader";
import { PageHeader } from "../components/page-header";
import {
  NoteRevealButton,
  NoteVisibilityBadge,
} from "../components/note-reveal-button";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/notes/$noteId"
)({
  // Saving does not update the cached note, so a kept route would show old text.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    try {
      const [, note] = await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...noteQueryOptions(params.noteId),
          staleTime: 0,
        }),
      ]);
      // The URL must name the campaign the note belongs to.
      if (note.campaignId !== params.campaignId) throw new Error("mismatch");
    } catch {
      throw notFound();
    }
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Note not found</h1>
      <p className="text-sm text-muted-foreground">
        It may not exist, or you may not have access to it.
      </p>
      <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
        Back to campaigns
      </Link>
    </section>
  ),
  component: NotePage,
});

function NotePage() {
  const { campaignId, noteId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const note = useNote(noteId).data;
  const rename = useNoteRename(campaignId, noteId);
  const [title, setTitle] = useState(note.title);
  const RichTextEditor = getEditor();
  // Other members edit a revealed body but cannot rename, hide, or archive the note.
  const canManage = campaign.isGm || note.isOwner;

  const commitTitle = () => {
    const next = title.trim();
    if (!next) return setTitle(note.title);
    if (next !== note.title) rename.mutate(next);
  };

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: "Notes", list: { campaignId, kind: "notes" } },
          { label: note.title },
        ]}
        title={note.title}
        description={
          !note.isOwner && note.ownerName ? `By ${note.ownerName}` : undefined
        }
        actions={
          <div className="flex items-center gap-3">
            <NoteVisibilityBadge revealed={note.revealed} />
            {canManage && (
              <NoteRevealButton
                campaignId={campaignId}
                id={note.id}
                revealed={note.revealed}
                title={note.title}
              />
            )}
          </div>
        }
      />
      {canManage && (
        <div className="space-y-2">
          <Input
            id="note-title-input"
            aria-label="Title"
            maxLength={200}
            value={title}
            onChange={event => setTitle(event.target.value)}
            onBlur={commitTitle}
            onKeyDown={event =>
              event.key === "Enter" && event.currentTarget.blur()
            }
          />
          {rename.error && (
            <Alert id="note-rename-error" variant="destructive">
              <AlertDescription>{rename.error.message}</AlertDescription>
            </Alert>
          )}
        </div>
      )}
      {/* The key gives each note its own editor; BlockNote reads its content only once. */}
      <RichTextEditor
        key={note.id}
        parent={{ kind: "note", id: note.id }}
        section="body"
        label="Text"
        hint="Write anything: a plot, a guide, a handout."
        initial={note.bodyJson}
        revision={note.bodyRevision}
      />
    </div>
  );
}
