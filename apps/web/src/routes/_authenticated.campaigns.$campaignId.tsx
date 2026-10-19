import { lazy, Suspense } from "react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import { Spinner } from "../components/ui/spinner";
import { buttonVariants } from "../components/ui/button";

// BlockNote only runs in the browser, so it stays out of the main bundle.
const RichTextEditor = lazy(() => import("../components/rich-text-editor"));

export const Route = createFileRoute("/_authenticated/campaigns/$campaignId")({
  loader: async ({ context, params }) => {
    try {
      await context.queryClient.ensureQueryData(
        campaignQueryOptions(params.campaignId)
      );
    } catch {
      throw notFound();
    }
  },
  notFoundComponent: () => (
    <section>
      <h1 className="text-3xl font-semibold">Campaign not found</h1>
      <Link
        to="/campaigns"
        className={buttonVariants({ variant: "link", className: "mt-6 px-0" })}
      >
        Back to campaigns
      </Link>
    </section>
  ),
  component: CampaignPage,
});

function CampaignPage() {
  const { campaignId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;

  return (
    <>
      <Link
        to="/campaigns"
        className={buttonVariants({ variant: "link", className: "mb-5 px-0" })}
      >
        Back to campaigns
      </Link>
      <h1 id="campaign-name" className="text-3xl font-semibold tracking-tight">
        {campaign.name}
      </h1>
      <Suspense fallback={<Spinner className="mt-8" />}>
        <RichTextEditor
          campaignId={campaign.id}
          section="description"
          label="Description"
          initial={campaign.descriptionJson}
          revision={campaign.descriptionRevision}
        />
        <RichTextEditor
          campaignId={campaign.id}
          section="progress_rewards"
          label="Progress and rewards"
          initial={campaign.progressRewardsJson}
          revision={campaign.progressRewardsRevision}
        />
      </Suspense>
    </>
  );
}
