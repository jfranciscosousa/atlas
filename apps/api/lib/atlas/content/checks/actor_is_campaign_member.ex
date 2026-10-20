defmodule Atlas.Content.Checks.ActorIsCampaignMember do
  @moduledoc """
  Passes when the actor is the GM or a player of the campaign the changeset names. The check
  reads the campaign as the actor, so a campaign the actor cannot read never passes and its
  existence stays hidden.
  """
  use Ash.Policy.SimpleCheck

  alias Atlas.Campaigns.Campaign

  @impl true
  def describe(_), do: "actor is a member of this campaign"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :campaign_id) do
      nil -> false
      campaign_id -> match?({:ok, %Campaign{}}, Ash.get(Campaign, campaign_id, actor: actor))
    end
  end

  def match?(_, _, _), do: false
end
