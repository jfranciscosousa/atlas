defmodule Atlas.Content.Checks.ActorIsCampaignGm do
  @moduledoc """
  Passes when the actor is the GM of the campaign the changeset names. A campaign the actor
  cannot read counts as not theirs, so the check never reveals whether it exists. A player
  can read the campaign but is not its GM.
  """
  use Ash.Policy.SimpleCheck

  alias Atlas.Campaigns.Campaign

  @impl true
  def describe(_), do: "actor is the GM of this campaign"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :campaign_id) do
      nil ->
        false

      campaign_id ->
        match?(
          {:ok, %Campaign{gm_id: gm_id}} when gm_id == actor.id,
          Ash.get(Campaign, campaign_id, actor: actor)
        )
    end
  end

  def match?(_, _, _), do: false
end
