defmodule Atlas.Images.Checks.ActorIsCampaignMember do
  @moduledoc """
  Passes when the actor is the GM or a player of at least one campaign. A campaign the actor
  cannot read does not count.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "actor plays or runs at least one campaign"

  @impl true
  def match?(nil, _, _), do: false
  def match?(actor, _, _), do: Ash.exists?(Atlas.Campaigns.Campaign, actor: actor)
end
