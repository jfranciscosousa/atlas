import { useState } from "react";
import { LockIcon } from "lucide-react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import { formatPlayedOn } from "../lib/session";
import {
  sessionQueryOptions,
  useSession,
  useSessionDetails,
} from "../hooks/use-sessions";
import { playerLogsQueryOptions } from "../hooks/use-player-logs";
import { campaignQueryOptions, useCampaign } from "../hooks/use-campaigns";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "../components/ui/tabs";
import { Input } from "../components/ui/input";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { SessionStatusBadge } from "../components/session-status-badge";
import { getEditor, loadEditor } from "../components/rich-text-editor-loader";
import { PlayerLogs } from "../components/player-logs";
import { PageHeader } from "../components/page-header";

export const Route = createFileRoute(
  "/_authenticated/campaigns/$campaignId_/sessions/$sessionId"
)({
  // Saving does not update the cached session, so a kept route would show old text.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    try {
      const [, session] = await Promise.all([
        context.queryClient.ensureQueryData(
          campaignQueryOptions(params.campaignId)
        ),
        context.queryClient.fetchQuery({
          ...sessionQueryOptions(params.sessionId),
          staleTime: 0,
        }),
        context.queryClient.fetchQuery({
          ...playerLogsQueryOptions(params.sessionId),
          staleTime: 0,
        }),
      ]);
      // The URL must name the campaign the session belongs to.
      if (session.campaignId !== params.campaignId) throw new Error("mismatch");
    } catch {
      throw notFound();
    }
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Session not found</h1>
      <p className="text-sm text-muted-foreground">
        It may not exist, or you may not have access to it.
      </p>
      <Link to="/campaigns" className={buttonVariants({ className: "mt-4" })}>
        Back to campaigns
      </Link>
    </section>
  ),
  component: SessionPage,
});

function SessionPage() {
  const { campaignId, sessionId } = Route.useParams();
  const campaign = useCampaign(campaignId).data;
  const session = useSession(sessionId).data;
  const details = useSessionDetails(campaignId, sessionId);
  const [title, setTitle] = useState(session.title ?? "");
  const RichTextEditor = getEditor();
  const heading = `Session ${session.number}`;

  const commitTitle = () => {
    const next = title.trim() || null;
    if (next !== session.title) details.mutate({ title: next });
  };

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: campaign.name, campaignId },
          { label: "Sessions", list: { campaignId, kind: "sessions" } },
          { label: heading },
        ]}
        title={heading}
        description={
          campaign.isGm
            ? undefined
            : [session.title, formatPlayedOn(session.playedOn)]
                .filter(Boolean)
                .join(" · ")
        }
        actions={
          <div className="flex items-center gap-3">
            <SessionStatusBadge status={session.status} />
            {campaign.isGm && (
              <Button
                id="session-status-button"
                variant={session.status === "done" ? "outline" : "default"}
                disabled={details.isPending}
                onClick={() =>
                  details.mutate({
                    status: session.status === "done" ? "in_prep" : "done",
                  })
                }
              >
                {session.status === "done"
                  ? "Move back to prep"
                  : "Mark as done"}
              </Button>
            )}
          </div>
        }
      />
      {campaign.isGm && (
        <div className="grid gap-3 sm:grid-cols-[1fr_auto]">
          <Input
            id="session-title-input"
            aria-label="Title"
            placeholder="Title (optional)"
            maxLength={200}
            value={title}
            onChange={event => setTitle(event.target.value)}
            onBlur={commitTitle}
            onKeyDown={event =>
              event.key === "Enter" && event.currentTarget.blur()
            }
          />
          <Input
            id="session-played-on-input"
            type="date"
            aria-label="Played on"
            value={session.playedOn ?? ""}
            onChange={event =>
              details.mutate({ playedOn: event.target.value || null })
            }
          />
          {details.error && (
            <Alert
              id="session-details-error"
              variant="destructive"
              className="sm:col-span-2"
            >
              <AlertDescription>{details.error.message}</AlertDescription>
            </Alert>
          )}
        </div>
      )}
      {/* The key gives each session its own editor; BlockNote reads its content only once. */}
      {/* keepMounted: a hidden editor keeps its text and its pending autosave. */}
      <Tabs
        defaultValue={
          campaign.isGm && session.status === "in_prep" ? "prep" : "log"
        }
      >
        <TabsList>
          {campaign.isGm && (
            <TabsTrigger value="prep">
              <LockIcon aria-hidden="true" className="size-3.5" />
              Prep
            </TabsTrigger>
          )}
          <TabsTrigger value="log">Log</TabsTrigger>
          <TabsTrigger value="player-logs">Player logs</TabsTrigger>
        </TabsList>
        {campaign.isGm && (
          <TabsContent value="prep" keepMounted>
            <RichTextEditor
              key={`${session.id}-prep`}
              parent={{ kind: "session", id: session.id }}
              section="prep"
              label="Prep"
              hideLabel
              hint="Secrets, encounters, and live notes during play. Only the GM sees this."
              initial={session.prepJson}
              revision={session.prepRevision}
            />
          </TabsContent>
        )}
        <TabsContent value="log" keepMounted>
          <RichTextEditor
            key={`${session.id}-log`}
            parent={{ kind: "session", id: session.id }}
            section="log"
            label="Log"
            hideLabel
            hint={
              campaign.isGm
                ? "What the table saw and learned. Every player can read this."
                : "What happened, as the GM recorded it."
            }
            initial={session.logJson}
            revision={session.logRevision}
            readOnly={!campaign.isGm}
          />
        </TabsContent>
        <TabsContent value="player-logs" keepMounted>
          <PlayerLogs sessionId={session.id} isGm={!!campaign.isGm} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
