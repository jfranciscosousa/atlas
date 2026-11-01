defmodule Atlas.Content.Checks.ActorRunsACampaign do
  @moduledoc """
  Passes when the actor is the GM of at least one campaign. A skill belongs to an account, not to
  a campaign, so this is the test for "is a GM".
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Atlas.Campaigns.Campaign

  @impl true
  def describe(_), do: "actor is the GM of a campaign"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, _context, _opts) do
    Campaign
    |> Ash.Query.filter(gm_id == ^actor.id)
    |> Ash.exists?(actor: actor)
  end
end
