import { useState } from "react";
import { ChevronRightIcon, LockIcon } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { notesQueryOptions, useNotesList } from "../hooks/use-notes";
import {
  characterQueryOptions,
  useCharacter,
  useCharacterRename,
} from "../hooks/use-characters";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "../components/ui/tabs";
import { Input } from "../components/ui/input";
import { buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { getEditor, loadEditor } from "../components/rich-text-editor-loader";
import { PageHeader } from "../components/page-header";
import { NoteVisibilityBadge } from "../components/note-visibility";
import { NewNoteButton } from "../components/new-note-button";
import { ClaimLink } from "../components/claim-link";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/characters/$characterId"
)({
  // Saving does not update the cached character, so a kept route would show old text.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    try {
      const [, character] = await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...characterQueryOptions(params.characterId),
          staleTime: 0,
        }),
        context.queryClient.fetchQuery({
          ...notesQueryOptions(params.campaignId),
          staleTime: 0,
        }),
      ]);
      // The URL must name the campaign the character belongs to.
      if (character.campaignId !== params.campaignId)
        throw new Error("mismatch");
    } catch {
      throw notFound();
    }
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Character not found</h1>
      <p className="text-sm text-muted-foreground">
        It may not exist, or you may not have access to it.
      </p>
      <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
        Back to campaigns
      </Link>
    </section>
  ),
  component: CharacterPage,
});

function CharacterPage() {
  const { campaignId, characterId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const character = useCharacter(characterId).data;
  const rename = useCharacterRename(campaignId, characterId);
  const notes = useNotesList(campaignId, false).data.filter(
    note => note.characterId === characterId
  );
  const [name, setName] = useState(character.name ?? "");
  const RichTextEditor = getEditor();
  const title = character.name ?? "Unnamed character";

  const commitName = () => {
    const next = name.trim() || null;
    if (next !== character.name) rename.mutate(next);
  };

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: "Characters", list: { campaignId, kind: "characters" } },
          { label: title },
        ]}
        title={title}
        description={`Played by ${character.playerName ?? "a player"}${character.claimed ? "" : " (unclaimed)"}`}
      />
      {character.claimPath && (
        <ClaimLink
          claimPath={character.claimPath}
          playerName={character.playerName}
        />
      )}
      {(character.isMine || campaign.isGm) && (
        <div className="grid gap-3">
          <Input
            id="character-name-input"
            aria-label="Name"
            placeholder="Character name"
            maxLength={200}
            value={name}
            onChange={event => setName(event.target.value)}
            onBlur={commitName}
            onKeyDown={event =>
              event.key === "Enter" && event.currentTarget.blur()
            }
          />
          {rename.error && (
            <Alert id="character-name-error" variant="destructive">
              <AlertDescription>{rename.error.message}</AlertDescription>
            </Alert>
          )}
        </div>
      )}
      {/* The key gives each character its own editor; BlockNote reads its content only once. */}
      {/* keepMounted: a hidden editor keeps its text and its pending autosave. */}
      <Tabs defaultValue="description">
        <TabsList>
          <TabsTrigger value="description">Description</TabsTrigger>
          {campaign.isGm && (
            <TabsTrigger value="secret-notes">
              <LockIcon aria-hidden="true" className="size-3.5" />
              Secret notes
            </TabsTrigger>
          )}
          <TabsTrigger value="notes">Notes</TabsTrigger>
        </TabsList>
        <TabsContent value="description" keepMounted>
          <RichTextEditor
            key={`${character.id}-description`}
            parent={{ kind: "character", id: character.id }}
            section="description"
            label="Description"
            hideLabel
            hint={
              character.isMine
                ? "Who your character is. Every player and the GM can read this."
                : `${title} is played by ${character.playerName ?? "a player"}. Every player and the GM can read this.`
            }
            initial={character.descriptionJson}
            readOnly={!character.isMine && !campaign.isGm}
          />
        </TabsContent>
        <TabsContent value="notes">
          <div className="space-y-4">
            <div className="flex items-center justify-between gap-3">
              <p className="text-sm text-muted-foreground">
                Notes linked to {title}. Only the people each note is shared
                with can read it.
              </p>
              {(campaign.isGm || character.isMine) && (
                <NewNoteButton
                  campaignId={campaignId}
                  characterId={characterId}
                />
              )}
            </div>
            <ul id="character-note-list" className="grid gap-3">
              {notes.map(note => (
                <li key={note.id}>
                  <Link
                    id={`character-note-${note.id}`}
                    to="/campaigns/$campaignId/notes/$noteId"
                    params={{ campaignId, noteId: note.id }}
                    className="group flex items-center gap-4 rounded-2xl border bg-card p-4 shadow-xs outline-none focus-visible:ring-3 focus-visible:ring-ring/30"
                  >
                    <span className="min-w-0 flex-1 truncate font-heading text-lg font-semibold">
                      {note.title}
                    </span>
                    <NoteVisibilityBadge
                      visibility={note.visibility}
                      characterName={note.characterName}
                    />
                    <ChevronRightIcon
                      aria-hidden="true"
                      className="size-5 text-muted-foreground"
                    />
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </TabsContent>
        {campaign.isGm && (
          <TabsContent value="secret-notes" keepMounted>
            <RichTextEditor
              key={`${character.id}-secret-notes`}
              parent={{ kind: "character", id: character.id }}
              section="secret_notes"
              label="Secret notes"
              hideLabel
              hint="What only you know about this character. Only the GM sees this."
              initial={character.secretNotesJson}
            />
          </TabsContent>
        )}
      </Tabs>
    </div>
  );
}
