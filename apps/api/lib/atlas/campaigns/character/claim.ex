defmodule Atlas.Campaigns.Character.Claim do
  @moduledoc """
  Finds the unclaimed character a claim token names and sets its campaign. A used or unknown
  token fails the same way, so a token reveals nothing. The GM of the campaign cannot play a
  character in it.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Atlas.Campaigns.Character

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    token = Ash.Changeset.get_argument(changeset, :token)

    Character
    |> Ash.Query.filter(claim_token == ^token and is_nil(user_id))
    |> Ash.Query.load(:campaign)
    # The token is the credential: the actor cannot read characters of campaigns they have not joined.
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Character{campaign: %{gm_id: gm_id}}} when gm_id == actor.id ->
        Ash.Changeset.add_error(changeset,
          field: :token,
          message: "You are the GM of this campaign."
        )

      {:ok, %Character{campaign_id: campaign_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :campaign_id, campaign_id)

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :token,
          message: "This claim link is no longer valid."
        )
    end
  end
end
