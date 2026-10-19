defmodule Atlas.Campaigns.CampaignPlayer.Join do
  @moduledoc """
  Sets the campaign from an active invitation token. A revoked or unknown token fails the same
  way, so a token reveals nothing. The GM of the campaign cannot become its player.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Atlas.Campaigns.Invitation

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    token = Ash.Changeset.get_argument(changeset, :token)

    Invitation
    |> Ash.Query.filter(token == ^token and is_nil(revoked_at))
    |> Ash.Query.load(:campaign)
    # The token is the credential: the actor cannot read invitations of campaigns they have not joined.
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Invitation{campaign: %{gm_id: gm_id}}} when gm_id == actor.id ->
        Ash.Changeset.add_error(changeset,
          field: :token,
          message: "You are the GM of this campaign."
        )

      {:ok, %Invitation{campaign_id: campaign_id}} ->
        Ash.Changeset.force_change_attribute(changeset, :campaign_id, campaign_id)

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :token,
          message: "This invitation link is no longer valid."
        )
    end
  end
end
