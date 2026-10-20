import { CalendarDays, Eye, ScrollText } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import { buttonVariants } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { getEditor, loadEditor } from "../components/rich-text-editor-loader";
import { PageHeader } from "../components/page-header";
import { CampaignReadOnly } from "../components/campaign-read-only";
import { InvitePlayersButton } from "../components/campaign-players";
import { CampaignAvatar } from "../components/campaign-avatar";

// BlockNote only runs in the browser, so it stays out of the main bundle.

export const Route = createFileRoute("/_authenticated/campaigns/$campaignId")({
  // Saving does not update the cached campaign, so a kept route would show old text.
  // The router must drop the route on leave and run the loader on every visit.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    try {
      // Always fetch: a cached copy predates the edits saved since it loaded.
      await context.queryClient.fetchQuery({
        ...campaignQueryOptions(params.campaignId),
        staleTime: 0,
      });
    } catch {
      throw notFound();
    }
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Campaign not found</h1>
      <p className="text-sm text-muted-foreground">
        It may not exist, or you may not have access to it.
      </p>
      <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
        Back to campaigns
      </Link>
    </section>
  ),
  component: CampaignPage,
});

function CampaignPage() {
  const { campaignId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const RichTextEditor = getEditor();

  if (!campaign.isGm)
    return (
      <CampaignReadOnly
        campaign={campaign}
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name },
        ]}
        actions={
          <div className="flex items-center gap-3">
            <Link
              id="campaign-sessions"
              to="/campaigns/$campaignId/sessions"
              params={{ campaignId: campaign.id }}
              className={buttonVariants({ variant: "outline" })}
            >
              <CalendarDays />
              Sessions
            </Link>
            <Link
              id="campaign-notes"
              to="/campaigns/$campaignId/notes"
              params={{ campaignId: campaign.id }}
              className={buttonVariants({ variant: "outline" })}
            >
              <ScrollText />
              Notes
            </Link>
          </div>
        }
      />
    );

  return (
    <div className="space-y-10">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name },
        ]}
        title={campaign.name}
        leading={
          <CampaignAvatar
            id={campaign.id}
            name={campaign.name}
            className="size-14 rounded-xl text-2xl"
          />
        }
        actions={
          <div className="flex items-center gap-3">
            <Badge variant="secondary">You are the GM</Badge>
            <InvitePlayersButton
              campaignId={campaign.id}
              gmName={campaign.gmName}
            />
            <Link
              id="campaign-sessions"
              to="/campaigns/$campaignId/sessions"
              params={{ campaignId: campaign.id }}
              className={buttonVariants({ variant: "outline" })}
            >
              <CalendarDays />
              Sessions
            </Link>
            <Link
              id="campaign-notes"
              to="/campaigns/$campaignId/notes"
              params={{ campaignId: campaign.id }}
              className={buttonVariants({ variant: "outline" })}
            >
              <ScrollText />
              Notes
            </Link>
            <Link
              id="preview-as-player"
              to="/campaigns/$campaignId/preview"
              params={{ campaignId: campaign.id }}
              className={buttonVariants({ variant: "outline" })}
            >
              <Eye />
              Preview as player
            </Link>
          </div>
        }
      />
      {/* The key gives each campaign its own editor; BlockNote reads its content only once. */}
      <RichTextEditor
        key={`${campaign.id}-description`}
        parent={{ kind: "campaign", id: campaign.id }}
        section="description"
        label="Description"
        hint="The world, the premise, and what the table should know first."
        initial={campaign.descriptionJson}
        revision={campaign.descriptionRevision}
      />
      <RichTextEditor
        key={`${campaign.id}-progress_rewards`}
        parent={{ kind: "campaign", id: campaign.id }}
        section="progress_rewards"
        label="Progress and rewards"
        hint="Milestones reached, loot earned, and what comes next."
        initial={campaign.progressRewardsJson}
        revision={campaign.progressRewardsRevision}
      />
    </div>
  );
}
