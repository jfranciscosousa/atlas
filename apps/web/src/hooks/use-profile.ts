import {
  queryOptions,
  useMutation,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query";
import {
  getProfile,
  updateProfile,
  type UpdateProfileInput,
} from "@atlas/api-client";

import { rpcOptions } from "../lib/rpc.ts";

const fields = ["id", "email", "displayName", "avatar"] as const;

export function profileQueryOptions(userId: string) {
  return queryOptions({
    queryKey: ["profile", userId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await getProfile({
        ...config,
        fields: [...fields],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not load your profile."
        );
      return result.data;
    },
    staleTime: 30_000,
    retry: false,
  });
}

export function useProfile(userId: string) {
  return useSuspenseQuery(profileQueryOptions(userId));
}

export function useProfileUpdate(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: UpdateProfileInput, { meta }) => {
      const result = await updateProfile({
        ...rpcOptions(meta),
        identity: userId,
        input,
        fields: [...fields],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not save your profile."
        );
      return result.data;
    },
    onSuccess: profile => {
      queryClient.setQueryData(profileQueryOptions(userId).queryKey, profile);
    },
  });
}
