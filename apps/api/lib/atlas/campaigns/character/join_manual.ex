defmodule Atlas.Campaigns.Character.JoinManual do
  @moduledoc """
  Creates the first character of the actor in the campaign the invitation names. An account that
  already plays in the campaign keeps its first character, so joining twice adds none.
  """
  use Ash.Resource.ManualCreate

  require Ash.Query

  alias Atlas.Campaigns.Character

  @impl true
  def create(changeset, _opts, %{actor: actor}) do
    campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)

    Character
    |> Ash.Query.filter(campaign_id == ^campaign_id and user_id == ^actor.id)
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        # The invitation token was the authorization; the actor is not a member yet.
        Ash.create(Character, %{campaign_id: campaign_id},
          action: :create,
          actor: actor,
          authorize?: false
        )

      other ->
        other
    end
  end
end
