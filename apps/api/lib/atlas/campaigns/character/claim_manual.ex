defmodule Atlas.Campaigns.Character.ClaimManual do
  @moduledoc """
  Gives the unclaimed character to the actor. The row is locked while it is read, so two people
  who open one link at once cannot both claim it: the second finds it claimed.
  """
  use Ash.Resource.ManualCreate

  require Ash.Query

  alias Atlas.Campaigns.Character

  @impl true
  def create(changeset, _opts, %{actor: actor}) do
    token = Ash.Changeset.get_argument(changeset, :token)

    Character
    |> Ash.Query.filter(claim_token == ^token and is_nil(user_id))
    |> Ash.Query.lock("FOR UPDATE")
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Character{} = character} ->
        character
        |> Ash.Changeset.for_update(:assign_player, %{user_id: actor.id}, authorize?: false)
        |> Ash.update()

      {:ok, nil} ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :token,
           message: "This claim link is no longer valid."
         )}

      other ->
        other
    end
  end
end
