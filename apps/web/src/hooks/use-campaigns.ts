import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createCampaign,
  getCampaign,
  getImageUrl,
  listCampaigns,
} from "@atlas/api-client";

import { rpcOptions } from "../lib/rpc.ts";
import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

export type Section = "description" | "progress_rewards";
type Meta = Parameters<typeof rpcOptions>[0];

export const campaignsKey = (userId: string) =>
  rpcKey(listCampaigns, undefined, userId);

export function campaignsQueryOptions(userId: string) {
  return rpcQuery(
    listCampaigns,
    run => run({ fields: ["id", "name", "isGm"] }),
    {
      fallback: "Could not load your campaigns.",
      scope: userId,
      staleTime: 30_000,
    }
  );
}

export function useCampaignsList(userId: string) {
  return useSuspenseQuery(campaignsQueryOptions(userId));
}

export function useCampaignCreate(userId: string) {
  return useRpcMutation(
    createCampaign,
    (run, name: string) => run({ input: { name }, fields: ["id"] }),
    {
      fallback: "Could not create the campaign.",
      invalidate: [campaignsKey(userId)],
    }
  );
}

export function campaignQueryOptions(campaignId: string) {
  return rpcQuery(
    getCampaign,
    run =>
      run({
        getBy: { id: campaignId },
        fields: [
          "id",
          "name",
          "isGm",
          "gmName",
          "descriptionJson",

          "progressRewardsJson",
        ],
      }),
    {
      fallback: "Campaign not found.",
      // The editors own the document after load. A refetch must not replace it.
      staleTime: Infinity,
    }
  );
}

export function useCampaign(campaignId: string) {
  return useSuspenseQuery(campaignQueryOptions(campaignId));
}

export async function fetchImageUrl(
  meta: Meta,
  imageId: string
): Promise<string> {
  const result = await getImageUrl({
    ...rpcOptions(meta),
    input: { id: imageId },
  });
  if (!result.success)
    throw new Error(result.errors[0]?.message ?? "Could not load the image.");
  return result.data;
}
