import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  ChevronRightIcon,
  WandSparklesIcon,
} from "lucide-react";
import { createFileRoute, Link } from "@tanstack/react-router";

import {
  skillsQueryOptions,
  useSkillArchive,
  useSkillRestore,
  useSkillsList,
} from "../hooks/use-skills";
import { useCampaignsList } from "../hooks/use-campaigns";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "../components/ui/empty";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { PageHeader } from "../components/page-header";
import { NewSkillButton } from "../components/new-skill-button";

export const Route = createFileRoute("/_authenticated/skills/")({
  // Optional, so links to the active view need no search.
  validateSearch: (search: Record<string, unknown>): { archived?: true } =>
    search.archived === true || search.archived === "true"
      ? { archived: true }
      : {},
  loaderDeps: ({ search }) => ({ archived: search.archived ?? false }),
  // A kept route would not show skills created or edited since it loaded.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, deps }) => {
    await context.queryClient.fetchQuery({
      ...skillsQueryOptions(context.user.id, deps.archived),
      staleTime: 0,
    });
  },
  component: SkillsPage,
});

function SkillsPage() {
  const { user } = Route.useRouteContext();
  const { archived = false } = Route.useSearch();
  const skills = useSkillsList(user.id, archived).data;
  // Only an account that is the GM of a campaign creates a skill.
  const canCreate = useCampaignsList(user.id).data.some(c => c.isGm);
  const archiveSkill = useSkillArchive(user.id);
  const restoreSkill = useSkillRestore(user.id);
  const archive = archived ? restoreSkill : archiveSkill;

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: archived ? "Archived skills" : "Skills" },
        ]}
        title={archived ? "Archived skills" : "Skills"}
        description="Procedures for your AI agents. They apply in every campaign and only you can read them. An agent connected through MCP lists them first and opens the ones that fit its task."
        actions={
          <div className="flex items-center gap-3">
            <Link
              id="skills-archived-toggle"
              to="/skills"
              search={archived ? {} : { archived: true }}
              className={buttonVariants({ variant: "outline" })}
            >
              {archived ? "Back to skills" : "Archived"}
            </Link>
            {!archived && canCreate && skills.length > 0 && <NewSkillButton />}
          </div>
        }
      />
      {archive.error && (
        <Alert id="skill-archive-error" variant="destructive">
          <AlertDescription>{archive.error.message}</AlertDescription>
        </Alert>
      )}
      {skills.length === 0 ? (
        <Empty id="skills-empty" className="border bg-card py-16">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <WandSparklesIcon aria-hidden="true" />
            </EmptyMedia>
            <EmptyTitle>
              {archived ? "No archived skills" : "No skills yet"}
            </EmptyTitle>
            <EmptyDescription>
              {archived
                ? "Skills you archive appear here, and you can restore them."
                : canCreate
                  ? "Write down how you want your agents to work: how to recap a session, how to build an NPC, how to name things."
                  : "Skills are for GMs. Create a campaign to write your own."}
            </EmptyDescription>
          </EmptyHeader>
          {!archived && canCreate && (
            <EmptyContent>
              <NewSkillButton>Create your first skill</NewSkillButton>
            </EmptyContent>
          )}
        </Empty>
      ) : (
        <ul id="skill-list" className="grid gap-3">
          {skills.map(skill => (
            <li
              key={skill.id}
              className="group flex items-center gap-2 rounded-2xl border bg-card shadow-xs transition-all focus-within:ring-3 focus-within:ring-ring/30 hover:-translate-y-0.5 hover:shadow-md"
            >
              <Link
                id={`skill-${skill.id}`}
                to="/skills/$skillId"
                params={{ skillId: skill.id }}
                className="flex min-w-0 flex-1 items-center gap-4 rounded-2xl p-4 outline-none"
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-heading text-lg font-semibold">
                    {skill.name}
                  </span>
                  {skill.description && (
                    <span className="block truncate text-sm text-muted-foreground">
                      {skill.description}
                    </span>
                  )}
                </span>
                <ChevronRightIcon
                  aria-hidden="true"
                  className="size-5 text-muted-foreground transition-transform group-hover:translate-x-0.5"
                />
              </Link>
              <Button
                id={`skill-${archived ? "restore" : "archive"}-${skill.id}`}
                variant="ghost"
                size="icon"
                className="mr-3"
                aria-label={
                  archived ? `Restore ${skill.name}` : `Archive ${skill.name}`
                }
                title={archived ? "Restore" : "Archive"}
                disabled={archive.isPending}
                onClick={() => archive.mutate(skill.id)}
              >
                {archived ? <ArchiveRestoreIcon /> : <ArchiveIcon />}
              </Button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
