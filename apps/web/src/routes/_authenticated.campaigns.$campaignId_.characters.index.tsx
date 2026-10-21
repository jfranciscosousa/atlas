import { ChevronRightIcon, UsersIcon } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import {
  charactersQueryOptions,
  useCharactersList,
} from "../hooks/use-characters";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "../components/ui/empty";
import { Badge } from "../components/ui/badge";
import { PageHeader } from "../components/page-header";
import { NewCharacterButton } from "../components/new-character-button";
import { InvitePlayersButton } from "../components/campaign-players";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/characters/"
)({
  // A kept route would not show characters created or renamed since it loaded.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    try {
      await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...charactersQueryOptions(params.campaignId),
          staleTime: 0,
        }),
      ]);
    } catch {
      throw notFound();
    }
  },
  component: CharactersPage,
});

function CharactersPage() {
  const { campaignId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const characters = useCharactersList(campaignId).data;

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: "Characters" },
        ]}
        title="Characters"
        description="Who is in this campaign and who plays them. Each player writes their own characters."
        actions={
          campaign.isGm ? (
            <InvitePlayersButton
              campaignId={campaignId}
              gmName={campaign.gmName}
            />
          ) : (
            <NewCharacterButton campaignId={campaignId} />
          )
        }
      />
      {characters.length === 0 ? (
        <Empty id="characters-empty" className="border bg-card py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <UsersIcon aria-hidden="true" />
            </EmptyMedia>
            <EmptyTitle>No characters yet</EmptyTitle>
            <EmptyDescription>
              {campaign.isGm
                ? "Share the invite link to add some."
                : "Nothing here yet."}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <ul id="character-list" className="grid gap-3">
          {characters.map(character => (
            <li key={character.id}>
              <Link
                id={`character-${character.id}`}
                to="/campaigns/$campaignId/characters/$characterId"
                params={{ campaignId, characterId: character.id }}
                className="group flex items-center gap-4 rounded-2xl border bg-card p-4 shadow-xs transition-all outline-none hover:-translate-y-0.5 hover:shadow-md focus-visible:ring-3 focus-visible:ring-ring/30"
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-heading text-lg font-semibold">
                    {character.name ?? "Unnamed character"}
                  </span>
                  <span className="block truncate text-sm text-muted-foreground">
                    Played by {character.playerName ?? "a player"}
                  </span>
                </span>
                {character.isMine && <Badge variant="secondary">You</Badge>}
                <ChevronRightIcon
                  aria-hidden="true"
                  className="size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
