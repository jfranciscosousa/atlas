defmodule Atlas.Content.Note.CheckCharacter do
  @moduledoc """
  A note links to a character of its own campaign. The `:character` visibility needs the link.
  The GM may link any character. A player may link only their own.
  """
  use Ash.Resource.Validation

  alias Atlas.Campaigns.{Campaign, Character}

  @impl true
  def validate(changeset, _opts, %{actor: actor}) do
    visibility = Ash.Changeset.get_attribute(changeset, :visibility)
    character_id = Ash.Changeset.get_attribute(changeset, :character_id)
    campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)

    cond do
      is_nil(character_id) and visibility == :character ->
        {:error, field: :character_id, message: "Choose the character that shares this note."}

      is_nil(character_id) ->
        :ok

      linkable?(actor, character_id, campaign_id) ->
        :ok

      true ->
        {:error, field: :character_id, message: "Choose one of your characters in this campaign."}
    end
  end

  defp linkable?(actor, character_id, campaign_id) do
    with {:ok, %Character{campaign_id: ^campaign_id} = character} <-
           Ash.get(Character, character_id, actor: actor),
         {:ok, %Campaign{gm_id: gm_id}} <- Ash.get(Campaign, campaign_id, actor: actor) do
      gm_id == actor.id or character.user_id == actor.id
    else
      _ -> false
    end
  end
end
