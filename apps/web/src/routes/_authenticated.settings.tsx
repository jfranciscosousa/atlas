import { createFileRoute } from "@tanstack/react-router";

import { mcpConnectionsQueryOptions } from "../hooks/use-mcp";
import { PageHeader } from "../components/page-header";
import { McpSettings } from "../components/mcp-settings";

export const Route = createFileRoute("/_authenticated/settings")({
  loader: async ({ context }) => {
    await context.queryClient.ensureQueryData(
      mcpConnectionsQueryOptions(context.user.id)
    );
  },
  component: Settings,
});

function Settings() {
  const { user } = Route.useRouteContext();
  return (
    <div className="mx-auto max-w-2xl space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: "Settings" },
        ]}
        title="Settings"
      />
      <div className="rounded-2xl border bg-card p-6 shadow-xs sm:p-8">
        <McpSettings userId={user.id} />
      </div>
    </div>
  );
}
