import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createInvitation,
  getActiveInvitation,
  getInvitationByToken,
  joinCampaign,
  revokeInvitation,
} from "@atlas/api-client";

import { campaignsKey } from "./use-campaigns.ts";
import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

const invitationKey = (campaignId: string) =>
  rpcKey(getActiveInvitation, { input: { campaignId } });

export function invitationByTokenQueryOptions(token: string) {
  return rpcQuery(
    getInvitationByToken,
    run =>
      run({
        input: { token },
        fields: ["campaignId", "campaignName", "gmName"],
      }),
    { fallback: "Could not check the invitation." }
  );
}

export function useJoinCampaign(userId: string) {
  return useRpcMutation(
    joinCampaign,
    (run, token: string) => run({ input: { token }, fields: ["campaignId"] }),
    {
      fallback: "Could not join the campaign.",
      invalidate: [campaignsKey(userId)],
    }
  );
}

export function activeInvitationQueryOptions(campaignId: string) {
  return rpcQuery(
    getActiveInvitation,
    run => run({ input: { campaignId }, fields: ["id", "token"] }),
    { fallback: "Could not load the invite link." }
  );
}

export function useInvitationCreate(campaignId: string) {
  return useRpcMutation(
    createInvitation,
    (run, _: void) => run({ input: { campaignId }, fields: ["id"] }),
    {
      fallback: "Could not create the invite link.",
      invalidate: [invitationKey(campaignId)],
    }
  );
}

export function useInvitationRevoke(campaignId: string) {
  return useRpcMutation(
    revokeInvitation,
    (run, id: string) => run({ identity: id, fields: ["id"] }),
    {
      fallback: "Could not revoke the invite link.",
      invalidate: [invitationKey(campaignId)],
    }
  );
}
