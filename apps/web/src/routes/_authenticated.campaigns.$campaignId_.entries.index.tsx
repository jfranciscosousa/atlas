import { useEffect, useRef, useState } from "react";
import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  GlobeIcon,
  SearchIcon,
} from "lucide-react";
import {
  createFileRoute,
  Link,
  notFound,
  useNavigate,
} from "@tanstack/react-router";

import { isEntryHit, queryTerms, sectionLabel } from "../lib/search";
import {
  clampPage,
  PAGE_SIZE,
  pageCount,
  pageSlice,
  parsePage,
} from "../lib/pagination";
import {
  ENTRY_KIND_LABELS,
  ENTRY_KINDS,
  isEntryKind,
  type EntryKind,
} from "../lib/entry-kinds";
import { useScopedSearch } from "../hooks/use-search";
import {
  entriesQueryOptions,
  useEntriesList,
  useEntryArchive,
  useEntryRestore,
} from "../hooks/use-entries";
import { useDebounced } from "../hooks/use-debounced";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import { Spinner } from "../components/ui/spinner";
import { Input } from "../components/ui/input";
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
import { Marked } from "../components/marked";
import { ENTRY_ICONS } from "../components/entry-icons";
import {
  EntryHiddenBadge,
  EntryHiddenToggle,
} from "../components/entry-badges";

const QUERY_MAX_LENGTH = 200;
const DEBOUNCE_MS = 150;

type Search = {
  kind?: EntryKind;
  archived?: true;
  /** The words in the search box. */
  q?: string;
  /** From 2 up. The first page has none. */
  page?: number;
};

type View = { kind?: EntryKind; archived?: boolean; q?: string; page?: number };

/** The URL of a view. A default value leaves no trace in the URL. */
const searchOf = ({ kind, archived, q, page }: View): Search => ({
  ...(kind && { kind }),
  ...(archived && { archived: true as const }),
  ...(q && { q }),
  ...(page && page > 1 && { page }),
});

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
    // A number in the URL, such as ?q=123, is still a query.
    ...(["string", "number"].includes(typeof search.q) &&
      String(search.q).trim() && {
        q: String(search.q).trim().slice(0, QUERY_MAX_LENGTH),
      }),
    ...(parsePage(search.page) && { page: parsePage(search.page) }),
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

type Row = {
  id: string;
  kind: EntryKind;
  name: string;
  /** Unknown when a hit is not in the loaded list. Then the row has no hidden controls. */
  hidden?: boolean;
  /** The text around the match. Only a search gives one. */
  snippet?: { section: string; text: string };
};

function EntriesPage() {
  const { campaignId } = Route.useParams();
  const { kind, archived = false, q = "", page = 1 } = Route.useSearch();
  const navigate = useNavigate();
  const campaign = useCampaign(campaignId).data;
  const all = useEntriesList(campaignId, { archived }).data;
  const archiveEntry = useEntryArchive(campaignId);
  const restoreEntry = useEntryRestore(campaignId);
  const archive = archived ? restoreEntry : archiveEntry;
  const noun = kind ? ENTRY_KIND_LABELS[kind].plural : "World entries";

  // The box types at once. The URL follows after a pause, and the search runs on the URL.
  const [input, setInput] = useState(q);
  const debounced = useDebounced(
    input.trim().slice(0, QUERY_MAX_LENGTH),
    DEBOUNCE_MS
  );
  const pushed = useRef(q);
  useEffect(() => {
    // The URL changed on its own, for example with Back. The box follows it.
    if (q === pushed.current) return;
    pushed.current = q;
    setInput(q);
  }, [q]);
  useEffect(() => {
    if (debounced === pushed.current) return;
    pushed.current = debounced;
    // A new query starts on the first page.
    void navigate({
      to: "/campaigns/$campaignId/entries",
      params: { campaignId },
      search: searchOf({ kind, archived, q: debounced }),
      replace: true,
    });
  }, [debounced]);

  // A query with no letters or digits is not a search. The API refuses it.
  const terms = queryTerms(q);
  const searching = terms.length > 0;
  const found = useScopedSearch(searching ? q : "", PAGE_SIZE, {
    campaignId,
    kinds: kind ? [kind] : ENTRY_KINDS,
    archived,
    offset: (page - 1) * PAGE_SIZE,
  });
  const waiting = searching && (debounced !== q || found.isFetching);

  const filtered = kind ? all.filter(entry => entry.kind === kind) : all;
  const byId = new Map(all.map(entry => [entry.id, entry]));
  const current = searching ? page : clampPage(page, filtered.length);
  const rows: Row[] = searching
    ? (found.data?.hits ?? []).flatMap(hit => {
        if (!isEntryHit(hit.kind)) return [];
        const section = hit.sections[0];
        const text = section?.blocks[0]?.text;
        return [
          {
            id: hit.id,
            kind: hit.kind,
            name: hit.title,
            hidden: byId.get(hit.id)?.hidden,
            ...(section &&
              text && { snippet: { section: section.section, text } }),
          },
        ];
      })
    : pageSlice(filtered, current);
  const hasNext = searching
    ? (found.data?.more ?? false)
    : current < pageCount(filtered.length);
  const firstRow = (current - 1) * PAGE_SIZE + 1;
  const view = { kind, archived, q: searching ? q : undefined };
  const entriesLink = (to: View) => ({
    to: "/campaigns/$campaignId/entries" as const,
    params: { campaignId },
    search: searchOf({ ...view, ...to }),
  });

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
                {...entriesLink({ archived: !archived })}
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
      {(all.length > 0 || input !== "") && (
        <div role="search" className="relative max-w-md">
          <SearchIcon
            aria-hidden="true"
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            id="entry-search"
            type="text"
            aria-label={`Search ${noun.toLowerCase()}`}
            autoComplete="off"
            autoCorrect="off"
            spellCheck={false}
            maxLength={QUERY_MAX_LENGTH}
            placeholder="Search names and text…"
            value={input}
            onChange={event => setInput(event.target.value)}
            onKeyDown={event => {
              if (event.key === "Escape" && input !== "") {
                event.preventDefault();
                setInput("");
              }
            }}
            className="pr-9 pl-9"
          />
          {waiting && (
            <Spinner className="absolute top-1/2 right-3 -translate-y-1/2 text-muted-foreground" />
          )}
        </div>
      )}
      <nav
        id="entry-kind-filter"
        aria-label="Kind of entry"
        className="flex flex-wrap gap-2"
      >
        <Link
          {...entriesLink({ kind: undefined })}
          className={buttonVariants({
            variant: kind ? "outline" : "default",
            size: "sm",
          })}
          aria-current={kind ? undefined : "page"}
        >
          All
          {!searching && (
            <span className="tabular-nums opacity-70">{all.length}</span>
          )}
        </Link>
        {ENTRY_KINDS.map(entryKind => {
          const Icon = ENTRY_ICONS[entryKind];
          return (
            <Link
              key={entryKind}
              id={`entry-filter-${entryKind}`}
              {...entriesLink({ kind: entryKind })}
              className={buttonVariants({
                variant: kind === entryKind ? "default" : "outline",
                size: "sm",
              })}
              aria-current={kind === entryKind ? "page" : undefined}
            >
              <Icon aria-hidden="true" data-icon="inline-start" />
              {ENTRY_KIND_LABELS[entryKind].plural}
              {!searching && (
                <span className="tabular-nums opacity-70">
                  {all.filter(entry => entry.kind === entryKind).length}
                </span>
              )}
            </Link>
          );
        })}
      </nav>
      {archive.error && (
        <Alert id="entry-archive-error" variant="destructive">
          <AlertDescription>{archive.error.message}</AlertDescription>
        </Alert>
      )}
      {searching && found.isError && (
        <Alert id="entry-search-error" variant="destructive">
          <AlertDescription>{found.error.message}</AlertDescription>
        </Alert>
      )}
      {rows.length === 0 ? (
        searching ? (
          !found.isError && (
            <Empty id="entries-search-empty" className="border bg-card py-16">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <SearchIcon aria-hidden="true" />
                </EmptyMedia>
                <EmptyTitle>
                  {waiting ? "Searching…" : `No matches for “${q}”`}
                </EmptyTitle>
                {!waiting && (
                  <EmptyDescription>
                    {page > 1
                      ? "There are no more matches."
                      : `No ${archived ? "archived " : ""}${noun.toLowerCase()} match. Try fewer or other words.`}
                  </EmptyDescription>
                )}
              </EmptyHeader>
              {!waiting && page > 1 && (
                <EmptyContent>
                  <Link
                    {...entriesLink({ page: 1 })}
                    className={buttonVariants({ variant: "outline" })}
                  >
                    Back to the first page
                  </Link>
                </EmptyContent>
              )}
            </Empty>
          )
        ) : (
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
        )
      ) : (
        <ul id="entry-list" className="grid gap-3">
          {rows.map(entry => {
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
                  <span className="grid min-w-0 flex-1 gap-1">
                    <span className="truncate font-heading text-lg font-semibold">
                      <Marked text={entry.name} terms={terms} />
                    </span>
                    {entry.snippet && (
                      <span className="line-clamp-2 text-xs/relaxed text-muted-foreground">
                        <span className="mr-1.5 rounded-md bg-secondary px-1.5 py-px text-[0.6875rem] font-medium text-secondary-foreground">
                          {sectionLabel(entry.snippet.section)}
                        </span>
                        <Marked text={entry.snippet.text} terms={terms} />
                      </span>
                    )}
                  </span>
                  {campaign.isGm && entry.hidden !== undefined && (
                    <EntryHiddenBadge hidden={entry.hidden} />
                  )}
                  <ChevronRightIcon
                    aria-hidden="true"
                    className="size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                  />
                </Link>
                {campaign.isGm && !archived && entry.hidden !== undefined && (
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
      {rows.length > 0 && (current > 1 || hasNext) && (
        <nav
          id="entries-pager"
          aria-label="Pages"
          className="flex items-center justify-between gap-3"
        >
          <p className="text-sm text-muted-foreground tabular-nums">
            {searching
              ? `Page ${current}`
              : `${firstRow}–${firstRow + rows.length - 1} of ${filtered.length}`}
          </p>
          <div className="flex gap-2">
            {current > 1 ? (
              <Link
                id="entries-previous"
                {...entriesLink({ page: current - 1 })}
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                <ChevronLeftIcon aria-hidden="true" data-icon="inline-start" />
                Previous
              </Link>
            ) : (
              <Button variant="outline" size="sm" disabled>
                <ChevronLeftIcon aria-hidden="true" data-icon="inline-start" />
                Previous
              </Button>
            )}
            {hasNext ? (
              <Link
                id="entries-next"
                {...entriesLink({ page: current + 1 })}
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                Next
                <ChevronRightIcon aria-hidden="true" data-icon="inline-end" />
              </Link>
            ) : (
              <Button variant="outline" size="sm" disabled>
                Next
                <ChevronRightIcon aria-hidden="true" data-icon="inline-end" />
              </Button>
            )}
          </div>
        </nav>
      )}
    </div>
  );
}
