import type { ReactNode } from "react";

import type { BlockNoteDocument } from "../lib/blocknote-schema";

import { getEditor } from "./rich-text-editor-loader";
import { PageHeader } from "./page-header";
import { PlayersList } from "./campaign-players";
import { CampaignAvatar } from "./campaign-avatar";

type Campaign = {
  id: string;
  name: string;
  gmName: string | null;
  descriptionJson: BlockNoteDocument;
  descriptionRevision: number;
  progressRewardsJson: BlockNoteDocument;
  progressRewardsRevision: number;
};

/** The campaign as a member reads it: both sections read-only, then who plays. */
export function CampaignReadOnly({
  campaign,
  crumbs,
  actions,
}: {
  campaign: Campaign;
  crumbs: { label: string; to?: "/campaigns" }[];
  actions?: ReactNode;
}) {
  const RichTextEditor = getEditor();

  return (
    <div className="space-y-10">
      <PageHeader
        crumbs={crumbs}
        title={campaign.name}
        actions={actions}
        leading={
          <CampaignAvatar
            id={campaign.id}
            name={campaign.name}
            className="size-14 rounded-xl text-2xl"
          />
        }
      />
      {/* The key gives each campaign its own editor; BlockNote reads its content only once. */}
      <RichTextEditor
        key={`${campaign.id}-description`}
        parent={{ kind: "campaign", id: campaign.id }}
        section="description"
        label="Description"
        hint="The world, the premise, and what the table should know first."
        initial={campaign.descriptionJson}
        revision={campaign.descriptionRevision}
        readOnly
      />
      <RichTextEditor
        key={`${campaign.id}-progress_rewards`}
        parent={{ kind: "campaign", id: campaign.id }}
        section="progress_rewards"
        label="Progress and rewards"
        hint="Milestones reached, loot earned, and what comes next."
        initial={campaign.progressRewardsJson}
        revision={campaign.progressRewardsRevision}
        readOnly
      />
      <section className="space-y-3">
        <h2 className="font-heading text-xl font-semibold">Players</h2>
        <PlayersList campaignId={campaign.id} gmName={campaign.gmName} />
      </section>
    </div>
  );
}
