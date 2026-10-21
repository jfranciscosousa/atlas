import type { ReactNode } from "react";

import type { BlockNoteDocument } from "../lib/blocknote-schema";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "./ui/tabs";
import { getEditor } from "./rich-text-editor-loader";
import { PageHeader } from "./page-header";
import { PlayersList } from "./campaign-players";
import { CampaignAvatar } from "./campaign-avatar";

type Campaign = {
  id: string;
  name: string;
  gmName: string | null;
  descriptionJson: BlockNoteDocument;
  progressRewardsJson: BlockNoteDocument;
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
      {/* keepMounted keeps both editors alive, as on the GM's page. */}
      <Tabs defaultValue="description">
        <TabsList>
          <TabsTrigger value="description">Description</TabsTrigger>
          <TabsTrigger value="progress">Progress and rewards</TabsTrigger>
        </TabsList>
        <TabsContent value="description" keepMounted>
          <RichTextEditor
            key={`${campaign.id}-description`}
            parent={{ kind: "campaign", id: campaign.id }}
            section="description"
            label="Description"
            hideLabel
            hint="The world, the premise, and what the table should know first."
            initial={campaign.descriptionJson}
            readOnly
          />
        </TabsContent>
        <TabsContent value="progress" keepMounted>
          <RichTextEditor
            key={`${campaign.id}-progress_rewards`}
            parent={{ kind: "campaign", id: campaign.id }}
            section="progress_rewards"
            label="Progress and rewards"
            hideLabel
            hint="Milestones reached, loot earned, and what comes next."
            initial={campaign.progressRewardsJson}
            readOnly
          />
        </TabsContent>
      </Tabs>
      <section className="space-y-3">
        <h2 className="font-heading text-xl font-semibold">Players</h2>
        <PlayersList campaignId={campaign.id} gmName={campaign.gmName} />
      </section>
    </div>
  );
}
