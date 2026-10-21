import { useState } from "react";
import { CheckIcon, CopyIcon, UserPlusIcon } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import { Input } from "./ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { Alert, AlertDescription } from "./ui/alert";
import {
  activeInvitationQueryOptions,
  useInvitationCreate,
  useInvitationRevoke,
} from "../hooks/use-players";
import { charactersQueryOptions } from "../hooks/use-characters";

/** The GM first, then the characters in creation order. Members and the GM can read it. */
export function CharactersList({
  campaignId,
  gmName,
}: {
  campaignId: string;
  gmName: string | null;
}) {
  const characters = useQuery(charactersQueryOptions(campaignId));

  return (
    <ul id="characters-list" className="divide-y rounded-xl border bg-card">
      <li className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
        <span className="font-medium">{gmName ?? "GM"}</span>
        <Badge variant="secondary">GM</Badge>
      </li>
      {characters.data?.map(character => (
        <li
          key={character.id}
          className="flex items-center justify-between gap-3 px-4 py-3 text-sm"
        >
          <span className="font-medium">
            {character.name ?? "Unnamed character"}
          </span>
          <span className="text-muted-foreground">
            played by {character.playerName ?? "a player"}
          </span>
        </li>
      ))}
      {characters.data?.length === 0 && (
        <li
          id="characters-empty"
          className="px-4 py-3 text-sm text-muted-foreground"
        >
          No characters yet. Share the invite link to add some.
        </li>
      )}
      {characters.error && (
        <li className="px-4 py-3 text-sm text-destructive">
          {characters.error.message}
        </li>
      )}
    </ul>
  );
}

function InviteLink({ campaignId }: { campaignId: string }) {
  const invitation = useQuery(activeInvitationQueryOptions(campaignId));
  const create = useInvitationCreate(campaignId);
  const revoke = useInvitationRevoke(campaignId);
  const [copied, setCopied] = useState(false);
  const active = invitation.data;
  const error = invitation.error ?? create.error ?? revoke.error;

  return (
    <div className="space-y-3">
      {active ? (
        <>
          <div className="flex gap-2">
            <Input
              id="invite-link"
              readOnly
              aria-label="Invite link"
              value={`${window.location.origin}/join/${active.token}`}
              onFocus={event => event.target.select()}
            />
            <Button
              id="invite-copy"
              variant="outline"
              onClick={async () => {
                await navigator.clipboard.writeText(
                  `${window.location.origin}/join/${active.token}`
                );
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
              }}
            >
              {copied ? (
                <CheckIcon aria-hidden="true" data-icon="inline-start" />
              ) : (
                <CopyIcon aria-hidden="true" data-icon="inline-start" />
              )}
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
          <p className="text-sm text-muted-foreground">
            Anyone with this link can join as a player until you revoke it.
            Revoking does not remove players who already joined.
          </p>
          <Button
            id="invite-revoke"
            variant="outline"
            isLoading={revoke.isPending}
            onClick={() => revoke.mutate(active.id)}
          >
            Revoke link
          </Button>
        </>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            {invitation.isPending
              ? "Loading the invite link…"
              : "There is no active invite link. Create one to invite players."}
          </p>
          <Button
            id="invite-create"
            disabled={invitation.isPending}
            isLoading={create.isPending}
            onClick={() => create.mutate()}
          >
            Create invite link
          </Button>
        </>
      )}
      {error && (
        <Alert id="invite-error" variant="destructive">
          <AlertDescription>{error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}

/** GM only: the invite link and the character list in one dialog. */
export function InvitePlayersButton({
  campaignId,
  gmName,
}: {
  campaignId: string;
  gmName: string | null;
}) {
  return (
    <Dialog>
      <DialogTrigger
        render={
          <Button id="invite-players" variant="outline">
            <UserPlusIcon aria-hidden="true" data-icon="inline-start" />
            Invite players
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Invite players</DialogTitle>
          <DialogDescription>
            Invite players with a link. They sign in or register, then join.
          </DialogDescription>
        </DialogHeader>
        <InviteLink campaignId={campaignId} />
        <CharactersList campaignId={campaignId} gmName={gmName} />
      </DialogContent>
    </Dialog>
  );
}
