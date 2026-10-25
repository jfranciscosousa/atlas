import { createFileRoute, Link } from "@tanstack/react-router";

import { PreviewContext } from "../lib/preview";
import { loadEntryPage } from "../lib/entry-route";
import { buttonVariants } from "../components/ui/button";
import { loadEditor } from "../components/rich-text-editor-loader";
import { EntryPage } from "../components/entry-page";

// An entry as a player reads it. The page is read-only and shows only what players see.
export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/preview_/entries/$entryId"
)({
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    await loadEntryPage(context.queryClient, params, true);
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Entry not found</h1>
      <p className="text-sm text-muted-foreground">
        Players cannot read this entry.
      </p>
      <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
        Back to campaigns
      </Link>
    </section>
  ),
  component: PreviewEntryRoute,
});

function PreviewEntryRoute() {
  const { campaignId, entryId } = Route.useParams();
  return (
    <PreviewContext.Provider value>
      <EntryPage campaignId={campaignId} entryId={entryId} preview />
    </PreviewContext.Provider>
  );
}
