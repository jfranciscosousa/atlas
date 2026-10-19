import { ArrowLeft, Eye } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import { buttonVariants } from "../components/ui/button";
import { loadEditor } from "../components/rich-text-editor-loader";
import { CampaignReadOnly } from "../components/campaign-read-only";

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
      <CampaignReadOnly
        campaign={campaign}
        crumbs={[{ label: campaign.name }]}
      />
    </div>
  );
}
