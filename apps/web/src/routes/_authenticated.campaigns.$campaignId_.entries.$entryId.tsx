import { createFileRoute, Link } from "@tanstack/react-router";

import { loadEntryPage } from "../lib/entry-route";
import { buttonVariants } from "../components/ui/button";
import { loadEditor } from "../components/rich-text-editor-loader";
import { EntryPage } from "../components/entry-page";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/entries/$entryId"
)({
  // Saving does not update the cached entry, so a kept route would show old text.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    await loadEntryPage(context.queryClient, params, false);
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Entry not found</h1>
      <p className="text-sm text-muted-foreground">
        It may not exist, or you may not have access to it.
      </p>
      <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
        Back to campaigns
      </Link>
    </section>
  ),
  component: EntryRoute,
});

function EntryRoute() {
  const { campaignId, entryId } = Route.useParams();
  return <EntryPage campaignId={campaignId} entryId={entryId} />;
}
