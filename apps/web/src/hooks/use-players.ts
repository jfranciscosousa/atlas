import {
  queryOptions,
  useMutation,
  useQueryClient,
} from "@tanstack/react-query";
import {
  createInvitation,
  getActiveInvitation,
  getInvitationByToken,
  joinCampaign,
  listCampaignPlayers,
  revokeInvitation,
} from "@atlas/api-client";

import { rpcOptions } from "../lib/rpc.ts";

export function invitationByTokenQueryOptions(token: string) {
  return queryOptions({
    queryKey: ["invitation-by-token", token],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await getInvitationByToken({
        ...config,
        input: { token },
        fields: ["campaignId", "campaignName", "gmName"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not check the invitation."
        );
      return result.data;
    },
    retry: false,
  });
}

export function useJoinCampaign(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (token: string, { meta }) => {
      const result = await joinCampaign({
        ...rpcOptions(meta),
        input: { token },
        fields: ["campaignId"],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not join the campaign."
        );
      return result.data;
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["campaigns", userId] }),
  });
}

export function activeInvitationQueryOptions(campaignId: string) {
  return queryOptions({
    queryKey: ["invitation", campaignId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await getActiveInvitation({
        ...config,
        input: { campaignId },
        fields: ["id", "token"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not load the invite link."
        );
      return result.data;
    },
    retry: false,
  });
}

export function useInvitationCreate(campaignId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (_: void, { meta }) => {
      const result = await createInvitation({
        ...rpcOptions(meta),
        input: { campaignId },
        fields: ["id"],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not create the invite link."
        );
      return result.data;
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["invitation", campaignId] }),
  });
}

export function useInvitationRevoke(campaignId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string, { meta }) => {
      const result = await revokeInvitation({
        ...rpcOptions(meta),
        identity: id,
        fields: ["id"],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not revoke the invite link."
        );
      return result.data;
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["invitation", campaignId] }),
  });
}

export function playersQueryOptions(campaignId: string) {
  return queryOptions({
    queryKey: ["players", campaignId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await listCampaignPlayers({
        ...config,
        input: { campaignId },
        fields: ["id", "displayName"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not load the players."
        );
      return result.data;
    },
    retry: false,
  });
}
