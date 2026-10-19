defmodule Atlas.Campaigns.Checks.CanEditSection do
  @moduledoc """
  Passes when the actor can run the campaign's `save_<section>` action on the campaign the
  changeset names. Uploading into a section needs the same access as editing it.
  """
  use Ash.Policy.SimpleCheck

  alias Atlas.Campaigns.Campaign

  @impl true
  def describe(_), do: "actor can edit this section of the campaign"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)
    section = Ash.Changeset.get_attribute(changeset, :section)

    with true <- not is_nil(campaign_id) and not is_nil(section),
         {:ok, %Campaign{} = campaign} <- Ash.get(Campaign, campaign_id, actor: actor) do
      Ash.can?({campaign, :"save_#{section}"}, actor)
    else
      _ -> false
    end
  end

  def match?(_, _, _), do: false
end
