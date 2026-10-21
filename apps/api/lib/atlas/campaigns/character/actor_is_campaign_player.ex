defmodule Atlas.Campaigns.Character.ActorIsCampaignPlayer do
  @moduledoc """
  Passes when the actor plays a character in the campaign the changeset names. The GM does not.
  The check reads the campaign as the actor, so a campaign the actor cannot read never passes.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Atlas.Campaigns.Campaign

  @impl true
  def describe(_), do: "actor plays a character in this campaign"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :campaign_id) do
      nil ->
        false

      campaign_id ->
        Campaign
        |> Ash.Query.filter(id == ^campaign_id and exists(characters, user_id == ^actor.id))
        |> Ash.exists?(actor: actor)
    end
  end

  def match?(_, _, _), do: false
end
