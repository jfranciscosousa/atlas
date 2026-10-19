import {
  queryOptions,
  useMutation,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query";
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

export type Section = "description" | "progress_rewards";
type Meta = Parameters<typeof rpcOptions>[0];

export function campaignsQueryOptions(userId: string) {
  return queryOptions({
    queryKey: ["campaigns", userId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await listCampaigns({
        ...config,
        fields: ["id", "name"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not load your campaigns."
        );
      return result.data;
    },
    staleTime: 30_000,
    retry: false,
  });
}

export function useCampaignsList(userId: string) {
  return useSuspenseQuery(campaignsQueryOptions(userId));
}

export function useCampaignCreate(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (name: string, { meta }) => {
      const result = await createCampaign({
        ...rpcOptions(meta),
        input: { name },
        fields: ["id"],
      });
      if (!result.success)
        throw new Error(
          result.errors[0]?.message ?? "Could not create the campaign."
        );
      return result.data;
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["campaigns", userId] }),
  });
}

export function campaignQueryOptions(campaignId: string) {
  return queryOptions({
    queryKey: ["campaign", campaignId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await getCampaign({
        ...config,
        getBy: { id: campaignId },
        fields: [
          "id",
          "name",
          "descriptionJson",
          "descriptionRevision",
          "progressRewardsJson",
          "progressRewardsRevision",
        ],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success)
        throw new Error(result.errors[0]?.message ?? "Campaign not found.");
      return result.data;
    },
    // The editors own the document after load. A refetch must not replace it.
    staleTime: Infinity,
    retry: false,
  });
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
