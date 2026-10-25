import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  ChevronRightIcon,
  GlobeIcon,
} from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import {
  ENTRY_KIND_LABELS,
  ENTRY_KINDS,
  isEntryKind,
  type EntryKind,
} from "../lib/entry-kinds";
import {
  entriesQueryOptions,
  useEntriesList,
  useEntryArchive,
  useEntryRestore,
} from "../hooks/use-entries";
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
import { NewEntryButton } from "../components/new-entry-button";
import { ENTRY_ICONS } from "../components/entry-icons";
import {
  EntryHiddenBadge,
  EntryHiddenToggle,
} from "../components/entry-badges";

type Search = {
  kind?: EntryKind;
  archived?: true;
};

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/entries/"
)({
  // Optional, so links to the active view need no search.
  validateSearch: (search: Record<string, unknown>): Search => ({
    ...(typeof search.kind === "string" &&
      isEntryKind(search.kind) && { kind: search.kind }),
    ...((search.archived === true || search.archived === "true") && {
      archived: true as const,
    }),
  }),
  loaderDeps: ({ search }) => ({
    archived: search.archived ?? false,
  }),
  // A kept route would not show entries created or edited since it loaded.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params, deps }) => {
    try {
      await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...entriesQueryOptions(params.campaignId, {
            archived: deps.archived,
          }),
          staleTime: 0,
        }),
      ]);
    } catch {
      throw notFound();
    }
  },
  component: EntriesPage,
});

function EntriesPage() {
  const { campaignId } = Route.useParams();
  const { kind, archived = false } = Route.useSearch();
  const campaign = useCampaign(campaignId).data;
  const all = useEntriesList(campaignId, { archived }).data;
  const entries = kind ? all.filter(entry => entry.kind === kind) : all;
  const archiveEntry = useEntryArchive(campaignId);
  const restoreEntry = useEntryRestore(campaignId);
  const archive = archived ? restoreEntry : archiveEntry;
  const noun = kind ? ENTRY_KIND_LABELS[kind].plural : "World entries";

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: archived ? "Archived world entries" : "World" },
        ]}
        title={archived ? "Archived world entries" : "World"}
        description={
          campaign.isGm
            ? "Anything of the world: NPCs, locations, factions, items, creatures and plots. An entry is free-form text. A new entry is hidden until you show it to the players."
            : "What the GM has shown you of the world."
        }
        actions={
          <div className="flex items-center gap-3">
            {campaign.isGm && (
              <Link
                id="entries-archived-toggle"
                to="/campaigns/$campaignId/entries"
                params={{ campaignId }}
                search={
                  archived
                    ? kind
                      ? { kind }
                      : {}
                    : { ...(kind && { kind }), archived: true }
                }
                className={buttonVariants({ variant: "outline" })}
              >
                {archived ? "Back to the world" : "Archived"}
              </Link>
            )}
            {campaign.isGm && !archived && all.length > 0 && (
              <NewEntryButton campaignId={campaignId} kind={kind} />
            )}
          </div>
        }
      />
      <nav
        id="entry-kind-filter"
        aria-label="Kind of entry"
        className="flex flex-wrap gap-2"
      >
        <Link
          to="/campaigns/$campaignId/entries"
          params={{ campaignId }}
          search={archived ? { archived: true } : {}}
          className={buttonVariants({
            variant: kind ? "outline" : "default",
            size: "sm",
          })}
          aria-current={kind ? undefined : "page"}
        >
          All
          <span className="tabular-nums opacity-70">{all.length}</span>
        </Link>
        {ENTRY_KINDS.map(entryKind => {
          const Icon = ENTRY_ICONS[entryKind];
          return (
            <Link
              key={entryKind}
              id={`entry-filter-${entryKind}`}
              to="/campaigns/$campaignId/entries"
              params={{ campaignId }}
              search={{
                kind: entryKind,
                ...(archived && { archived: true as const }),
              }}
              className={buttonVariants({
                variant: kind === entryKind ? "default" : "outline",
                size: "sm",
              })}
              aria-current={kind === entryKind ? "page" : undefined}
            >
              <Icon aria-hidden="true" data-icon="inline-start" />
              {ENTRY_KIND_LABELS[entryKind].plural}
              <span className="tabular-nums opacity-70">
                {all.filter(entry => entry.kind === entryKind).length}
              </span>
            </Link>
          );
        })}
      </nav>
      {archive.error && (
        <Alert id="entry-archive-error" variant="destructive">
          <AlertDescription>{archive.error.message}</AlertDescription>
        </Alert>
      )}
      {entries.length === 0 ? (
        <Empty id="entries-empty" className="border bg-card py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <GlobeIcon aria-hidden="true" />
            </EmptyMedia>
            <EmptyTitle>
              {archived
                ? `No archived ${noun.toLowerCase()}`
                : `No ${noun.toLowerCase()} yet`}
            </EmptyTitle>
            <EmptyDescription>
              {archived
                ? "Entries you archive appear here, and you can restore them."
                : campaign.isGm
                  ? "Create one. Players see it only after you show it to them."
                  : "The GM has not shown you any yet."}
            </EmptyDescription>
          </EmptyHeader>
          {campaign.isGm && !archived && (
            <EmptyContent>
              <NewEntryButton campaignId={campaignId} kind={kind}>
                {kind
                  ? `Create your first ${ENTRY_KIND_LABELS[kind].label}`
                  : "Create your first entry"}
              </NewEntryButton>
            </EmptyContent>
          )}
        </Empty>
      ) : (
        <ul id="entry-list" className="grid gap-3">
          {entries.map(entry => {
            const Icon = ENTRY_ICONS[entry.kind];
            return (
              <li
                key={entry.id}
                className="group flex items-center gap-2 rounded-2xl border bg-card shadow-xs transition-all focus-within:ring-3 focus-within:ring-ring/30 hover:-translate-y-0.5 hover:shadow-md"
              >
                <Link
                  id={`entry-${entry.id}`}
                  to="/campaigns/$campaignId/entries/$entryId"
                  params={{ campaignId, entryId: entry.id }}
                  className="flex min-w-0 flex-1 items-center gap-4 rounded-2xl p-4 outline-none"
                >
                  <Icon
                    aria-label={ENTRY_KIND_LABELS[entry.kind].label}
                    className="size-5 shrink-0 text-muted-foreground"
                  />
                  <span className="min-w-0 flex-1 truncate font-heading text-lg font-semibold">
                    {entry.name}
                  </span>
                  {campaign.isGm && <EntryHiddenBadge hidden={entry.hidden} />}
                  <ChevronRightIcon
                    aria-hidden="true"
                    className="size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                  />
                </Link>
                {campaign.isGm && !archived && (
                  <EntryHiddenToggle
                    campaignId={campaignId}
                    entryId={entry.id}
                    hidden={entry.hidden}
                    name={entry.name}
                    icon
                  />
                )}
                {campaign.isGm && (
                  <Button
                    id={`entry-${archived ? "restore" : "archive"}-${entry.id}`}
                    variant="ghost"
                    size="icon"
                    className="mr-3"
                    aria-label={
                      archived
                        ? `Restore ${entry.name}`
                        : `Archive ${entry.name}`
                    }
                    title={archived ? "Restore" : "Archive"}
                    disabled={archive.isPending}
                    onClick={() => archive.mutate(entry.id)}
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
