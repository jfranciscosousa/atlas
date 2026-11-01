import { useState } from "react";
import { createFileRoute, Link, notFound } from "@tanstack/react-router";

import {
  skillQueryOptions,
  useSkill,
  useSkillUpdate,
} from "../hooks/use-skills";
import { Label } from "../components/ui/label";
import { Input } from "../components/ui/input";
import { buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { getEditor, loadEditor } from "../components/rich-text-editor-loader";
import { PageHeader } from "../components/page-header";

export const Route = createFileRoute("/_authenticated/skills/$skillId")({
  // Saving does not update the cached skill, so a kept route would show old text.
  gcTime: 0,
  staleTime: 0,
  loader: async ({ context, params }) => {
    const editor = loadEditor();
    try {
      await context.queryClient.fetchQuery({
        ...skillQueryOptions(params.skillId),
        staleTime: 0,
      });
    } catch {
      throw notFound();
    }
    await editor;
  },
  notFoundComponent: () => (
    <section className="flex min-h-[50vh] flex-col items-center justify-center gap-2 text-center">
      <h1 className="text-3xl font-semibold">Skill not found</h1>
      <p className="text-sm text-muted-foreground">
        It may not exist, or you may not have access to it.
      </p>
      <Link to="/skills" className={buttonVariants({ className: "mt-4" })}>
        Back to skills
      </Link>
    </section>
  ),
  component: SkillPage,
});

function SkillPage() {
  const { user } = Route.useRouteContext();
  const { skillId } = Route.useParams();
  const skill = useSkill(skillId).data;
  const update = useSkillUpdate(user.id, skillId);
  const [name, setName] = useState(skill.name);
  const [description, setDescription] = useState(skill.description);
  const RichTextEditor = getEditor();

  const commit = () => {
    const next = { name: name.trim(), description: description.trim() };
    if (!next.name) return setName(skill.name);
    if (next.name !== skill.name || next.description !== skill.description)
      update.mutate(next);
  };

  return (
    <div className="space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: "Skills", to: "/skills" },
          { label: skill.name },
        ]}
        title={skill.name}
        description="Only you can read this skill. Your AI agents read it through MCP."
      />
      <div className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="skill-name-input">Name</Label>
          <Input
            id="skill-name-input"
            maxLength={200}
            value={name}
            onChange={event => setName(event.target.value)}
            onBlur={commit}
            onKeyDown={event =>
              event.key === "Enter" && event.currentTarget.blur()
            }
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="skill-description-input">When to use it</Label>
          <Input
            id="skill-description-input"
            maxLength={1000}
            placeholder="Use when the GM asks for a session recap."
            value={description}
            onChange={event => setDescription(event.target.value)}
            onBlur={commit}
            onKeyDown={event =>
              event.key === "Enter" && event.currentTarget.blur()
            }
          />
          <p className="text-sm text-muted-foreground">
            An agent reads this line first, and opens the skill only if it fits
            the task.
          </p>
        </div>
        {update.error && (
          <Alert id="skill-update-error" variant="destructive">
            <AlertDescription>{update.error.message}</AlertDescription>
          </Alert>
        )}
      </div>
      {/* The key gives each skill its own editor; BlockNote reads its content only once. */}
      <RichTextEditor
        key={skill.id}
        parent={{ kind: "skill", id: skill.id }}
        section="body"
        label="Procedure"
        hint="Write the steps an agent follows when the skill applies."
        initial={skill.bodyJson}
      />
    </div>
  );
}
