import { useState } from "react";
import { PlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";

import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { useSkillCreate } from "../hooks/use-skills";

// There is no creation form: the skill exists at once and opens for editing in place.
export function NewSkillButton({
  children = "New skill",
}: {
  children?: string;
}) {
  const navigate = useNavigate();
  const create = useSkillCreate();
  // Stays set until the skill page is open, so the list never shows between create and navigate.
  const [busy, setBusy] = useState(false);

  async function createAndOpen() {
    setBusy(true);
    try {
      const skill = await create.mutateAsync();
      await navigate({
        to: "/skills/$skillId",
        params: { skillId: skill.id },
      });
    } catch {
      // The mutation exposes the error below.
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col items-end gap-2">
      <Button
        id="skill-new"
        isLoading={busy}
        disabled={busy}
        onClick={() => void createAndOpen()}
      >
        <PlusIcon aria-hidden="true" data-icon="inline-start" />
        {children}
      </Button>
      {create.error && (
        <Alert id="skill-error" variant="destructive">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
