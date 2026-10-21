defmodule Atlas.Campaigns.PlayerLog.ActorIsSessionPlayer do
  @moduledoc """
  Passes when the actor is a player of the campaign that owns the session the changeset names.
  The GM is not a player. The check reads the session as the actor, so a session the actor
  cannot read never passes and its existence stays hidden.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Atlas.Campaigns.Session

  @impl true
  def describe(_), do: "actor plays in the campaign of this session"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :session_id) do
      nil ->
        false

      session_id ->
        Session
        |> Ash.Query.filter(id == ^session_id and exists(campaign.players, user_id == ^actor.id))
        |> Ash.exists?(actor: actor)
    end
  end

  def match?(_, _, _), do: false
end
