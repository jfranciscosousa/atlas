import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  ChevronRightIcon,
  ScrollTextIcon,
} from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import {
  notesQueryOptions,
  useNoteArchive,
  useNoteRestore,
  useNotesList,
} from "../hooks/use-notes";
import { charactersQueryOptions } from "../hooks/use-characters";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "../components/ui/empty";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { PageHeader } from "../components/page-header";
import {
  NoteVisibilityBadge,
  NoteVisibilityMenu,
} from "../components/note-visibility";
import { NewNoteButton } from "../components/new-note-button";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/notes/"
)({
  // Optional, so links to the active view need no search.
  validateSearch: (search: Record<string, unknown>): { archived?: true } =>
    search.archived === true || search.archived === "true"
      ? { archived: true }
      : {},
  loaderDeps: ({ search }) => ({ archived: search.archived ?? false }),
  // A kept route would not show notes created or edited since it loaded.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params, deps }) => {
    try {
      await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.ensureQueryData(
          charactersQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...notesQueryOptions(params.campaignId, deps.archived),
          staleTime: 0,
        }),
      ]);
    } catch {
      throw notFound();
    }
  },
  component: NotesPage,
});

function NotesPage() {
  const { campaignId } = Route.useParams();
  const { archived = false } = Route.useSearch();
  const campaign = useCampaign(campaignId).data;
  const notes = useNotesList(campaignId, archived).data;
  const archiveNote = useNoteArchive(campaignId);
  const restoreNote = useNoteRestore(campaignId);
  const archive = archived ? restoreNote : archiveNote;

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: archived ? "Archived notes" : "Notes" },
        ]}
        title={archived ? "Archived notes" : "Notes"}
        description={
          campaign.isGm
            ? "Plots, guides, handouts, and anything else that fits nowhere. A new note is visible to you and the GM until you share it."
            : "Notes shared with you, and your own. A new note is visible to you and the GM until you share it."
        }
        actions={
          <div className="flex items-center gap-3">
            <Link
              id="notes-archived-toggle"
              to="/campaigns/$campaignId/notes"
              params={{ campaignId }}
              search={archived ? {} : { archived: true }}
              className={buttonVariants({ variant: "outline" })}
            >
              {archived ? "Back to notes" : "Archived"}
            </Link>
            {!archived && notes.length > 0 && (
              <NewNoteButton campaignId={campaignId} />
            )}
          </div>
        }
      />
      {archive.error && (
        <Alert id="note-archive-error" variant="destructive">
          <AlertDescription>{archive.error.message}</AlertDescription>
        </Alert>
      )}
      {notes.length === 0 ? (
        <Empty id="notes-empty" className="border bg-card py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <ScrollTextIcon aria-hidden="true" />
            </EmptyMedia>
            <EmptyTitle>
              {archived ? "No archived notes" : "No notes yet"}
            </EmptyTitle>
            <EmptyDescription>
              {archived
                ? "Notes you archive appear here, and you can restore them."
                : campaign.isGm
                  ? "Write down a plot, a campaign guide, or a handout."
                  : "Write a note of your own, or wait for the GM to share one."}
            </EmptyDescription>
          </EmptyHeader>
          {!archived && (
            <EmptyContent>
              <NewNoteButton campaignId={campaignId}>
                Create your first note
              </NewNoteButton>
            </EmptyContent>
          )}
        </Empty>
      ) : (
        <ul id="note-list" className="grid gap-3">
          {notes.map(note => {
            // Other members read a shared note but cannot change what it is.
            const canManage = campaign.isGm || note.isOwner;
            return (
              <li
                key={note.id}
                className="group flex items-center gap-2 rounded-2xl border bg-card shadow-xs transition-all focus-within:ring-3 focus-within:ring-ring/30 hover:-translate-y-0.5 hover:shadow-md"
              >
                <Link
                  id={`note-${note.id}`}
                  to="/campaigns/$campaignId/notes/$noteId"
                  params={{ campaignId, noteId: note.id }}
                  className="flex min-w-0 flex-1 items-center gap-4 rounded-2xl p-4 outline-none"
                >
                  <span className="min-w-0 flex-1 truncate font-heading text-lg font-semibold">
                    {note.title}
                  </span>
                  {!note.isOwner && note.ownerName && (
                    <span className="hidden text-sm text-muted-foreground sm:inline">
                      {note.ownerName}
                    </span>
                  )}
                  <NoteVisibilityBadge
                    visibility={note.visibility}
                    characterName={note.characterName}
                  />
                  <ChevronRightIcon
                    aria-hidden="true"
                    className="size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                  />
                </Link>
                {canManage && !archived && (
                  <NoteVisibilityMenu
                    campaignId={campaignId}
                    id={note.id}
                    visibility={note.visibility}
                    characterId={note.characterId}
                    isGm={campaign.isGm ?? false}
                    title={note.title}
                    icon
                  />
                )}
                {canManage && (
                  <Button
                    id={`note-${archived ? "restore" : "archive"}-${note.id}`}
                    variant="ghost"
                    size="icon"
                    className="mr-3"
                    aria-label={
                      archived
                        ? `Restore ${note.title}`
                        : `Archive ${note.title}`
                    }
                    title={archived ? "Restore" : "Archive"}
                    disabled={archive.isPending}
                    onClick={() => archive.mutate(note.id)}
                  >
                    {archived ? <ArchiveRestoreIcon /> : <ArchiveIcon />}
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
