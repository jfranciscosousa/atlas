import { useState } from "react";
import { ArchiveIcon, ArchiveRestoreIcon, LockIcon } from "lucide-react";
import { Link, useNavigate } from "@tanstack/react-router";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "./ui/tabs";
import { Input } from "./ui/input";
import { Button, buttonVariants } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { getEditor } from "./rich-text-editor-loader";
import { PageHeader } from "./page-header";
import { EntryRelations } from "./entry-relations";
import { EntryDetails } from "./entry-details";
import { EntryHiddenBadge, EntryHiddenToggle } from "./entry-badges";
import { ENTRY_KIND_LABELS } from "../lib/entry-kinds";
import { useTabState } from "../hooks/use-search-target";
import {
  useEntry,
  useEntryArchive,
  useEntryRename,
  useEntryRestore,
} from "../hooks/use-entries";
import { useCampaign } from "../hooks/use-campaigns";

const SECTION_TABS = {
  description: "description",
  secret_notes: "secret-notes",
};

/**
 * A world entry. The GM edits everything. A player reads what the GM shows. In preview, the GM
 * reads the page as a player does: read-only, with no secret notes.
 */
export function EntryPage({
  campaignId,
  entryId,
  preview = false,
}: {
  campaignId: string;
  entryId: string;
  preview?: boolean;
}) {
  const navigate = useNavigate();
  const campaign = useCampaign(campaignId).data;
  const entry = useEntry(entryId).data;
  const rename = useEntryRename(campaignId, entryId);
  const archive = useEntryArchive(campaignId, entryId);
  const restore = useEntryRestore(campaignId, entryId);
  const [name, setName] = useState(entry.name);
  const [tab, setTab] = useTabState(SECTION_TABS, "description");
  const RichTextEditor = getEditor();
  const canManage = !!campaign.isGm && !preview;
  const kind = ENTRY_KIND_LABELS[entry.kind];

  const commitName = () => {
    const next = name.trim();
    if (!next) return setName(entry.name);
    if (next !== entry.name) rename.mutate(next);
  };

  async function archiveAndLeave() {
    try {
      await archive.mutateAsync(entry.id);
      await navigate({
        to: "/campaigns/$campaignId/entries",
        params: { campaignId },
        search: {},
      });
    } catch {
      // The mutation exposes the error below.
    }
  }

  const error = rename.error ?? archive.error ?? restore.error;

  return (
    <div className="space-y-8">
      {preview && (
        <div
          id="preview-banner"
          className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm"
        >
          <span className="font-medium">
            Previewing as a player. This page is read-only.
          </span>
          <Link
            id="back-to-preview"
            to="/campaigns/$campaignId/preview"
            params={{ campaignId }}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            Back to the preview
          </Link>
        </div>
      )}
      <PageHeader
        crumbs={
          preview
            ? [{ label: campaign.name }, { label: entry.name }]
            : [
                { label: "Campaigns", to: "/campaigns" },
                { label: campaign.name, campaignId },
                { label: "World", list: { campaignId, kind: "entries" } },
                { label: entry.name },
              ]
        }
        title={entry.name}
        description={kind.label}
        actions={
          canManage && (
            <div className="flex flex-wrap items-center gap-3">
              <EntryHiddenBadge hidden={entry.hidden} />
              <EntryHiddenToggle
                campaignId={campaignId}
                entryId={entry.id}
                hidden={entry.hidden}
                name={entry.name}
              />
              {!entry.archivedAt && (
                <Button
                  id="entry-archive"
                  variant="outline"
                  disabled={archive.isPending}
                  onClick={() => void archiveAndLeave()}
                >
                  <ArchiveIcon aria-hidden="true" data-icon="inline-start" />
                  Archive
                </Button>
              )}
            </div>
          )
        }
      />
      {canManage && entry.archivedAt && (
        <Alert id="entry-archived">
          <AlertDescription className="flex flex-wrap items-center justify-between gap-3">
            This entry is archived. Players do not see it.
            <Button
              id="entry-restore"
              variant="outline"
              size="sm"
              disabled={restore.isPending}
              onClick={() => restore.mutate(entry.id)}
            >
              <ArchiveRestoreIcon aria-hidden="true" data-icon="inline-start" />
              Restore
            </Button>
          </AlertDescription>
        </Alert>
      )}
      {canManage && (
        <div className="space-y-2">
          <Input
            id="entry-name-input"
            aria-label="Name"
            maxLength={200}
            value={name}
            onChange={event => setName(event.target.value)}
            onBlur={commitName}
            onKeyDown={event =>
              event.key === "Enter" && event.currentTarget.blur()
            }
          />
        </div>
      )}
      {error && (
        <Alert id="entry-error" variant="destructive">
          <AlertDescription>{error.message}</AlertDescription>
        </Alert>
      )}
      <EntryDetails
        campaignId={campaignId}
        entry={entry}
        canManage={canManage}
        preview={preview}
      />
      <EntryRelations
        campaignId={campaignId}
        endId={entry.id}
        endKind={entry.kind}
        canManage={canManage}
        preview={preview}
      />
      {/* The key gives each entry its own editor; BlockNote reads its content only once. */}
      {/* keepMounted: a hidden editor keeps its text and its pending autosave. */}
      {canManage ? (
        <Tabs value={tab} onValueChange={setTab}>
          <TabsList>
            <TabsTrigger value="description">Description</TabsTrigger>
            <TabsTrigger value="secret-notes">
              <LockIcon aria-hidden="true" className="size-3.5" />
              Secret notes
            </TabsTrigger>
          </TabsList>
          <TabsContent value="description" keepMounted>
            <RichTextEditor
              key={`${entry.id}-description`}
              parent={{ kind: entry.kind, id: entry.id }}
              section="description"
              label="Description"
              hideLabel
              hint="What the players read once you show this entry."
              initial={entry.descriptionJson}
            />
          </TabsContent>
          <TabsContent value="secret-notes" keepMounted>
            <RichTextEditor
              key={`${entry.id}-secret-notes`}
              parent={{ kind: entry.kind, id: entry.id }}
              section="secret_notes"
              label="Secret notes"
              hideLabel
              hint="What only you know about this entry. Only the GM sees this."
              initial={entry.secretNotesJson ?? []}
            />
          </TabsContent>
        </Tabs>
      ) : (
        <RichTextEditor
          key={`${entry.id}-description`}
          parent={{ kind: entry.kind, id: entry.id }}
          section="description"
          label="Description"
          initial={entry.descriptionJson}
          readOnly
        />
      )}
    </div>
  );
}
