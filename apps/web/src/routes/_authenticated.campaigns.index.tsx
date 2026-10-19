import { ChevronRightIcon, SwordsIcon } from "lucide-react";
import { createFileRoute, Link } from "@tanstack/react-router";

import { useCampaignsList } from "../hooks/use-campaigns";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "../components/ui/empty";
import { Badge } from "../components/ui/badge";
import { PageHeader } from "../components/page-header";
import { NewCampaignButton } from "../components/new-campaign-button";
import { CampaignAvatar } from "../components/campaign-avatar";

export const Route = createFileRoute("/_authenticated/campaigns/")({
  component: Campaigns,
});

function Campaigns() {
  const { user } = Route.useRouteContext();
  const campaigns = useCampaignsList(user.id).data;

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[{ label: "Campaigns" }]}
        title="Campaigns"
        description="The worlds you run or play in. Open one to read or write its story."
        actions={campaigns.length > 0 && <NewCampaignButton userId={user.id} />}
      />
      {campaigns.length === 0 ? (
        <Empty id="campaigns-empty" className="border bg-card py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <SwordsIcon aria-hidden="true" />
            </EmptyMedia>
            <EmptyTitle>No campaigns yet</EmptyTitle>
            <EmptyDescription>
              Create your first campaign. You become its GM and can describe the
              world, track progress, and add images.
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <NewCampaignButton userId={user.id}>
              Create your first campaign
            </NewCampaignButton>
          </EmptyContent>
        </Empty>
      ) : (
        <ul
          id="campaign-list"
          className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3"
        >
          {campaigns.map(campaign => (
            <li key={campaign.id}>
              <Link
                id={`campaign-${campaign.id}`}
                to="/campaigns/$campaignId"
                params={{ campaignId: campaign.id }}
                className="group flex h-full items-center gap-4 rounded-2xl border bg-card p-4 shadow-xs transition-all outline-none hover:-translate-y-0.5 hover:shadow-md focus-visible:ring-3 focus-visible:ring-ring/30"
              >
                <CampaignAvatar
                  id={campaign.id}
                  name={campaign.name}
                  className="size-14 rounded-xl text-2xl"
                />
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-heading text-lg font-semibold">
                    {campaign.name}
                  </span>
                  <Badge variant="secondary" className="mt-1">
                    {campaign.isGm ? "You are the GM" : "Player"}
                  </Badge>
                </span>
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
