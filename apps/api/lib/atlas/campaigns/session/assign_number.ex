defmodule Atlas.Campaigns.Session.AssignNumber do
  @moduledoc """
  Gives a new session the next number of its campaign, starting at 1. The campaign row stays
  locked until the transaction ends, so two creates at once never take the same number.
  """
  use Ash.Resource.Change

  alias Atlas.Repo

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_attribute(changeset, :campaign_id) do
        # The policy rejects a create without a campaign.
        nil -> changeset
        campaign_id -> assign(changeset, Ecto.UUID.dump!(campaign_id))
      end
    end)
  end

  defp assign(changeset, id) do
    Repo.query!("SELECT 1 FROM campaigns WHERE id = $1 FOR UPDATE", [id])

    %{rows: [[number]]} =
      Repo.query!("SELECT COALESCE(MAX(number), 0) + 1 FROM sessions WHERE campaign_id = $1", [id])

    Ash.Changeset.force_change_attribute(changeset, :number, number)
  end
end
