import { useSuspenseQuery } from "@tanstack/react-query";
import { getProfile, updateProfile } from "@atlas/api-client";

import { rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

const fields = ["id", "email", "displayName", "avatar"] as const;

export function profileQueryOptions(userId: string) {
  return rpcQuery(getProfile, run => run({ fields: [...fields] }), {
    fallback: "Could not load your profile.",
    scope: userId,
    staleTime: 30_000,
  });
}

export function useProfile(userId: string) {
  return useSuspenseQuery(profileQueryOptions(userId));
}

export function useProfileUpdate(userId: string) {
  return useRpcMutation(
    updateProfile,
    (run, input) => run({ identity: userId, input, fields: [...fields] }),
    {
      fallback: "Could not save your profile.",
      onSuccess: (profile, queryClient) =>
        queryClient.setQueryData(profileQueryOptions(userId).queryKey, profile),
    }
  );
}
