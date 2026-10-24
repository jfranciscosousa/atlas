import { CalendarDaysIcon, ChevronRightIcon } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { formatPlayedOn, sessionLabel } from "../lib/session";
import { sessionsQueryOptions, useSessionsList } from "../hooks/use-sessions";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "../components/ui/empty";
import { SessionStatusBadge } from "../components/session-status-badge";
import { PageHeader } from "../components/page-header";
import { NewSessionButton } from "../components/new-session-button";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/sessions/"
)({
  // A kept route would not show sessions created or renamed since it loaded.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    try {
      await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...sessionsQueryOptions(params.campaignId),
          staleTime: 0,
        }),
      ]);
    } catch {
      throw notFound();
    }
  },
  component: SessionsPage,
});

function SessionsPage() {
  const { campaignId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const sessions = useSessionsList(campaignId).data;

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: "Sessions" },
        ]}
        title="Sessions"
        description={
          campaign.isGm
            ? "Prep each session in private. Write the log for the table after you play."
            : "The GM's log of each session."
        }
        actions={
          campaign.isGm &&
          sessions.length > 0 && <NewSessionButton campaignId={campaignId} />
        }
      />
      {sessions.length === 0 ? (
        <Empty id="sessions-empty" className="border bg-card py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <CalendarDaysIcon aria-hidden="true" />
            </EmptyMedia>
            <EmptyTitle>No sessions yet</EmptyTitle>
            <EmptyDescription>
              {campaign.isGm
                ? "Create a session to prepare it and, later, to write its log."
                : "Nothing here yet."}
            </EmptyDescription>
          </EmptyHeader>
          {campaign.isGm && (
            <EmptyContent>
              <NewSessionButton campaignId={campaignId}>
                Create your first session
              </NewSessionButton>
            </EmptyContent>
          )}
        </Empty>
      ) : (
        <ul id="session-list" className="grid gap-3">
          {sessions.map(session => (
            <li key={session.id}>
              <Link
                id={`session-${session.id}`}
                to="/campaigns/$campaignId/sessions/$sessionId"
                params={{ campaignId, sessionId: session.id }}
                className="group flex items-center gap-4 rounded-2xl border bg-card p-4 shadow-xs transition-all outline-none hover:-translate-y-0.5 hover:shadow-md focus-visible:ring-3 focus-visible:ring-ring/30"
              >
                <span className="min-w-0 flex-1 truncate font-heading text-lg font-semibold">
                  {sessionLabel(session)}
                </span>
                {session.playedOn && (
                  <span className="hidden text-sm text-muted-foreground sm:inline">
                    {formatPlayedOn(session.playedOn)}
                  </span>
                )}
                <SessionStatusBadge status={session.status} />
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
