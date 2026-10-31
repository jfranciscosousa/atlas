import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";

import { sessionRequest } from "../lib/auth";
import { useClaimCharacter } from "../hooks/use-characters";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";

type Claim = {
  characterName: string | null;
  playerLabel: string | null;
  campaignName: string;
  gmName: string | null;
};

export const Route = createFileRoute("/_public/claim/$token")({
  beforeLoad: async ({ context }) => {
    const session = await sessionRequest("/api/session", {
      queryClient: context.queryClient,
    });
    return { user: session.user };
  },
  // The page shows the invitation before the person has an account, so this is no RPC call.
  loader: async ({ params }): Promise<{ claim: Claim | null }> => {
    const response = await fetch(`/api/claims/${params.token}`, {
      headers: { Accept: "application/json" },
    });
    return { claim: response.ok ? ((await response.json()) as Claim) : null };
  },
  gcTime: 0,
  component: ClaimPage,
});

function ClaimPage() {
  const { token } = Route.useParams();
  const { claim } = Route.useLoaderData();
  const { user } = Route.useRouteContext();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const claimCharacter = useClaimCharacter(user?.id ?? "");
  const redirect = `/claim/${token}`;

  if (!claim)
    return (
      <div id="claim-invalid">
        <h1 className="text-3xl font-semibold tracking-tight">
          This claim link is not valid
        </h1>
        <p className="mt-4 text-sm leading-7 text-muted-foreground">
          Someone already used it, or it is wrong. Ask your GM for a new one.
        </p>
        <Link
          to={user ? "/campaigns" : "/sign-in"}
          className={buttonVariants({ className: "mt-6" })}
        >
          {user ? "Back to campaigns" : "Sign in"}
        </Link>
      </div>
    );

  return (
    <div id="claim-page">
      <p className="text-sm text-muted-foreground">{claim.campaignName}</p>
      <h1 className="mt-1 text-3xl font-semibold tracking-tight">
        {claim.characterName ?? "Unnamed character"}
      </h1>
      <p className="mt-4 text-sm leading-7 text-muted-foreground">
        {claim.gmName ?? "The GM"} prepared this character for{" "}
        {claim.playerLabel ?? "you"}. Claim it to play it and join the campaign.
      </p>
      {user ? (
        <div className="mt-8 space-y-4">
          {claimCharacter.error && (
            <Alert id="claim-error" variant="destructive">
              <AlertDescription>
                {claimCharacter.error.message}
              </AlertDescription>
            </Alert>
          )}
          <Button
            id="claim-character"
            className="w-full"
            isLoading={claimCharacter.isPending}
            onClick={async () => {
              const claimed = await claimCharacter
                .mutateAsync(token)
                .catch(() => null);
              if (claimed) {
                // The campaign list in the shell must include the new campaign.
                await queryClient.invalidateQueries();
                await navigate({
                  to: "/campaigns/$campaignId/characters/$characterId",
                  params: {
                    campaignId: claimed.campaignId,
                    characterId: claimed.id,
                  },
                });
              }
            }}
          >
            Claim character
          </Button>
        </div>
      ) : (
        <div className="mt-8 space-y-3">
          <Link
            id="claim-register"
            to="/register"
            search={{ redirect }}
            className={buttonVariants({ className: "w-full" })}
          >
            Create an account to claim it
          </Link>
          <Link
            id="claim-sign-in"
            to="/sign-in"
            search={{ redirect }}
            className={buttonVariants({
              variant: "outline",
              className: "w-full",
            })}
          >
            I already have an account
          </Link>
          <p className="pt-2 text-center text-xs text-muted-foreground">
            After you sign in or confirm your email, we will return you here to
            claim your character.
          </p>
        </div>
      )}
    </div>
  );
}
