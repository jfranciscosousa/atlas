import { useSuspenseQuery } from "@tanstack/react-query";
import {
  archiveSkill,
  createSkill,
  getSkill,
  listSkills,
  restoreSkill,
  updateSkill,
} from "@atlas/api-client";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

// Skills belong to an account, so the user scopes every list. It matches the active and the
// archived list.
const skillsKey = (userId: string) => rpcKey(listSkills, undefined, userId);

export function skillsQueryOptions(userId: string, archived = false) {
  return rpcQuery(
    listSkills,
    run =>
      run({
        input: { archived },
        fields: ["id", "name", "description"],
      }),
    { fallback: "Could not load the skills.", scope: userId }
  );
}

export function useSkillsList(userId: string, archived: boolean) {
  return useSuspenseQuery(skillsQueryOptions(userId, archived));
}

/** Archives or restores a skill from the list. Both views refetch. */
export function useSkillArchive(userId: string) {
  return useRpcMutation(
    archiveSkill,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not update the skill.",
      invalidate: [skillsKey(userId)],
    }
  );
}

export function useSkillRestore(userId: string) {
  return useRpcMutation(
    restoreSkill,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not update the skill.",
      invalidate: [skillsKey(userId)],
    }
  );
}

// No list refetch here: the list route reloads on every visit, and a refetch would flash the
// new skill in the list before its page opens.
export function useSkillCreate() {
  return useRpcMutation(
    createSkill,
    (run, _: void) =>
      run({
        input: { name: "Untitled skill", description: "" },
        fields: ["id"],
      }),
    { fallback: "Could not create the skill." }
  );
}

export function skillQueryOptions(skillId: string) {
  return rpcQuery(
    getSkill,
    run =>
      run({
        getBy: { id: skillId },
        fields: ["id", "name", "description", "bodyJson"],
      }),
    {
      fallback: "Skill not found.",
      // The editor owns the document after load. A refetch must not replace it.
      staleTime: Infinity,
    }
  );
}

export function useSkill(skillId: string) {
  return useSuspenseQuery(skillQueryOptions(skillId));
}

/** Saves the name and the description. The open skill keeps its body. */
export function useSkillUpdate(userId: string, skillId: string) {
  return useRpcMutation(
    updateSkill,
    (run, input: { name: string; description: string }) =>
      run({ identity: skillId, input, fields: ["name", "description"] }),
    {
      fallback: "Could not save the skill.",
      // Refetching the skill would hand the open editor an older body revision.
      onSuccess: (shared, queryClient) =>
        queryClient.setQueryData(
          skillQueryOptions(skillId).queryKey,
          skill => skill && { ...skill, ...shared }
        ),
      invalidate: [skillsKey(userId)],
    }
  );
}
