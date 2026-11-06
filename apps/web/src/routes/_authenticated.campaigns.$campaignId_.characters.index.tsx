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
import { NewUnclaimedCharacterButton } from "../components/new-unclaimed-character-button";
import { NewCharacterButton } from "../components/new-character-button";
import {
  CHARACTER_STATUS_LABELS,
  CharacterStatusBadge,
} from "../components/character-status";
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
  const active = characters.filter(character => character.status === "active");

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
            <div className="flex flex-wrap gap-2">
              <NewUnclaimedCharacterButton campaignId={campaignId} />
              <InvitePlayersButton
                campaignId={campaignId}
                gmName={campaign.gmName}
              />
            </div>
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
                ? "Share the invite link, or prepare a character."
                : "Nothing here yet."}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <>
          {active.length > 0 ? (
            <CharacterList id="character-list" characters={active} />
          ) : (
            <p id="characters-no-active" className="text-muted-foreground">
              No active characters.
            </p>
          )}
          {/* Retired and dead characters keep everything. Only the list sets them apart. */}
          {INACTIVE_STATUSES.map(status => {
            const group = characters.filter(
              character => character.status === status
            );
            if (group.length === 0) return null;
            return (
              <details key={status} id={`characters-${status}`}>
                <summary className="cursor-pointer text-lg font-semibold select-none">
                  {CHARACTER_STATUS_LABELS[status]} ({group.length})
                </summary>
                <CharacterList
                  id={`character-list-${status}`}
                  characters={group}
                />
              </details>
            );
          })}
        </>
      )}
    </div>
  );
}

const INACTIVE_STATUSES = ["retired", "dead"] as const;

type ListedCharacter = ReturnType<typeof useCharactersList>["data"][number];

function CharacterList({
  id,
  characters,
}: {
  id: string;
  characters: ListedCharacter[];
}) {
  const { campaignId } = Route.useParams();
  return (
    <ul id={id} className="mt-3 grid grid-cols-1 gap-3">
      {characters.map(character => (
        <li key={character.id}>
          <Link
            id={`character-${character.id}`}
            to="/campaigns/$campaignId/characters/$characterId"
            params={{ campaignId, characterId: character.id }}
            className="group grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-2 rounded-2xl border bg-card p-3.5 shadow-xs transition-all outline-none hover:-translate-y-0.5 hover:shadow-md focus-visible:ring-3 focus-visible:ring-ring/30 sm:flex sm:gap-4 sm:p-4"
          >
            <span className="min-w-0 flex-1">
              <span className="block truncate font-heading text-lg font-semibold">
                {character.name ?? "Unnamed character"}
              </span>
              <span className="block truncate text-sm text-muted-foreground">
                Played by {character.playerName ?? "a player"}
              </span>
            </span>
            <span className="col-start-1 row-start-2 flex flex-wrap items-center gap-1.5 empty:hidden sm:contents">
              <CharacterStatusBadge status={character.status} />
              {character.isMine && <Badge variant="secondary">You</Badge>}
              {!character.claimed && <Badge variant="outline">Unclaimed</Badge>}
            </span>
            <ChevronRightIcon
              aria-hidden="true"
              className="col-start-2 row-start-1 size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5"
            />
          </Link>
        </li>
      ))}
    </ul>
  );
}
