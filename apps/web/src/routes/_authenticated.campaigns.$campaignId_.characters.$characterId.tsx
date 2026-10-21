import { useState } from "react";
import { LockIcon } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

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
        description={`Played by ${character.playerName ?? "a player"}`}
      />
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
