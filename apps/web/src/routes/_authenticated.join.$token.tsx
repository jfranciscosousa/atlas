import {
  createFileRoute,
  Link,
  redirect,
  useNavigate,
} from "@tanstack/react-router";

import {
  invitationByTokenQueryOptions,
  useJoinCampaign,
} from "../hooks/use-players";
import { campaignsQueryOptions } from "../hooks/use-campaigns";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { CampaignAvatar } from "../components/campaign-avatar";

export const Route = createFileRoute("/_authenticated/join/$token")({
  loader: async ({ context, params }) => {
    const invitation = await context.queryClient.fetchQuery({
      ...invitationByTokenQueryOptions(params.token),
      staleTime: 0,
    });
    if (!invitation) return { invitation: null };

    // The GM and players who already joined go straight to the campaign.
    const campaigns = await context.queryClient.fetchQuery({
      ...campaignsQueryOptions(context.user.id),
      staleTime: 0,
    });
    if (campaigns.some(campaign => campaign.id === invitation.campaignId))
      throw redirect({
        to: "/campaigns/$campaignId",
        params: { campaignId: invitation.campaignId },
      });
    return { invitation };
  },
  gcTime: 0,
  component: JoinPage,
});

function JoinPage() {
  const { token } = Route.useParams();
  const { invitation } = Route.useLoaderData();
  const { user } = Route.useRouteContext();
  const navigate = useNavigate();
  const join = useJoinCampaign(user.id);

  if (!invitation)
    return (
      <section
        id="join-invalid"
        className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center"
      >
        <h1 className="text-3xl font-semibold">This invitation is not valid</h1>
        <p className="text-sm text-muted-foreground">
          The link was revoked or is wrong. Ask your GM for a new one.
        </p>
        <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
          Back to campaigns
        </Link>
      </section>
    );

  return (
    <section
      id="join-page"
      className="mx-auto flex min-h-[50vh] max-w-md flex-col items-center justify-center gap-4 text-center"
    >
      <CampaignAvatar
        id={invitation.campaignId}
        name={invitation.campaignName ?? ""}
        className="size-20 rounded-2xl text-3xl"
      />
      <h1 className="text-3xl font-semibold">{invitation.campaignName}</h1>
      <p className="text-sm text-muted-foreground">
        {invitation.gmName ?? "The GM"} invited you to play in this campaign.
      </p>
      {join.error && (
        <Alert id="join-error" variant="destructive">
          <AlertDescription>{join.error.message}</AlertDescription>
        </Alert>
      )}
      <Button
        id="join-campaign"
        isLoading={join.isPending}
        onClick={async () => {
          const joined = await join.mutateAsync(token).catch(() => null);
          if (joined)
            await navigate({
              to: "/campaigns/$campaignId",
              params: { campaignId: joined.campaignId },
            });
        }}
      >
        Join campaign
      </Button>
    </section>
  );
}
