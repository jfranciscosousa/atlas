import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createCampaign,
  getCampaign,
  getCampaignImageUrl,
  listCampaigns,
  saveCampaignDescription,
  saveCampaignProgressRewards,
} from "@atlas/api-client";

import type { BlockNoteDocument } from "../lib/blocknote-schema";
import type { SaveOutcome } from "../lib/autosave.ts";

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
          "descriptionRevision",
          "progressRewardsJson",
          "progressRewardsRevision",
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

export async function saveCampaignSection(
  meta: Meta,
  campaignId: string,
  section: Section,
  json: BlockNoteDocument,
  expectedRevision: number
): Promise<SaveOutcome> {
  const input = { json, schemaVersion: 1, expectedRevision };
  const config = { ...rpcOptions(meta), identity: campaignId, input };
  let result;
  try {
    result =
      section === "description"
        ? await saveCampaignDescription({
            ...config,
            fields: ["descriptionRevision"],
          })
        : await saveCampaignProgressRewards({
            ...config,
            fields: ["progressRewardsRevision"],
          });
  } catch {
    return {
      ok: false,
      kind: "failed",
      message: "Could not reach the server. Your edits are kept. Try again.",
    };
  }

  if (result.success) {
    const data = result.data as Record<string, number>;
    return {
      ok: true,
      revision: data.descriptionRevision ?? data.progressRewardsRevision!,
    };
  }
  const error = result.errors[0];
  return {
    ok: false,
    kind: error?.type === "stale_revision" ? "stale" : "failed",
    message: error?.message ?? "Could not save.",
  };
}

export async function fetchImageUrl(
  meta: Meta,
  campaignId: string,
  section: Section,
  imageId: string
): Promise<string> {
  const result = await getCampaignImageUrl({
    ...rpcOptions(meta),
    input: { id: imageId, campaignId, section },
  });
  if (!result.success)
    throw new Error(result.errors[0]?.message ?? "Could not load the image.");
  return result.data;
}
