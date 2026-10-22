defmodule Atlas.Campaigns.Session.ActorIsSessionGm do
  @moduledoc """
  Passes when the actor is the GM of the campaign that owns the session the action input names
  by `id`. The check reads the session as the actor, so a session the actor cannot read never
  passes and its existence stays hidden.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Atlas.Campaigns.Session

  @impl true
  def describe(_), do: "actor is the GM of this session's campaign"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.ActionInput{} = input}, _opts) do
    case Ash.ActionInput.get_argument(input, :id) do
      nil ->
        false

      id ->
        Session
        |> Ash.Query.filter(id == ^id and exists(campaign, gm_id == ^actor.id))
        |> Ash.exists?(actor: actor)
    end
  end

  def match?(_, _, _), do: false
end
