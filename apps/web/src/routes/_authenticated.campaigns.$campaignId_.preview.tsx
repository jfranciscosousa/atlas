import { ArrowLeft, Eye } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import { buttonVariants } from "../components/ui/button";
import { getEditor, loadEditor } from "../components/rich-text-editor-loader";
import { PageHeader } from "../components/page-header";
import { CampaignAvatar } from "../components/campaign-avatar";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/preview"
)({
  // Same cache rule as the editing page: the cached campaign predates saved edits.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    try {
      await context.queryClient.fetchQuery({
        ...campaignQueryOptions(params.campaignId),
        staleTime: 0,
      });
    } catch {
      throw notFound();
    }
    await editor;
  },
  component: PreviewPage,
});

function PreviewPage() {
  const { campaignId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const RichTextEditor = getEditor();

  return (
    <div className="space-y-10">
      <div
        id="preview-banner"
        className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm"
      >
        <span className="flex items-center gap-2 font-medium">
          <Eye className="size-4" />
          Previewing as a player. This page is read-only.
        </span>
        <Link
          id="back-to-editing"
          to="/campaigns/$campaignId"
          params={{ campaignId: campaign.id }}
          className={buttonVariants({ variant: "outline", size: "sm" })}
        >
          <ArrowLeft />
          Back to editing
        </Link>
      </div>
      <PageHeader
        crumbs={[{ label: campaign.name }]}
        title={campaign.name}
        leading={
          <CampaignAvatar
            id={campaign.id}
            name={campaign.name}
            className="size-14 rounded-xl text-2xl"
          />
        }
      />
      <RichTextEditor
        key={`${campaign.id}-description`}
        campaignId={campaign.id}
        section="description"
        label="Description"
        hint="The world, the premise, and what the table should know first."
        initial={campaign.descriptionJson}
        revision={campaign.descriptionRevision}
        readOnly
      />
      <RichTextEditor
        key={`${campaign.id}-progress_rewards`}
        campaignId={campaign.id}
        section="progress_rewards"
        label="Progress and rewards"
        hint="Milestones reached, loot earned, and what comes next."
        initial={campaign.progressRewardsJson}
        revision={campaign.progressRewardsRevision}
        readOnly
      />
    </div>
  );
}
