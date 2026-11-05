defmodule Atlas.Mcp.AudienceCheck do
  @moduledoc """
  Warnings for an MCP edit that puts a pointer to secret text into a section that players read.

  A mention of a hidden world entry in text that players read tells them that the
  entry exists: the mention stores its kind and ID, and the player sees "Restricted entry". The
  edit still applies. The warning tells the agent what it did, so the agent can undo it or ask the
  GM.
  """
  require Ash.Query

  alias Atlas.Audience
  alias Atlas.Content.{Entry, EntrySpec}

  @entry_kinds Enum.map(EntrySpec.kinds(), &Atom.to_string/1)

  @doc """
  The warnings for `mentions`, the `{kind, id}` pairs that an edit added to a section with this
  audience. `campaign_id` is the campaign of the section. The actor reads the entries, so a
  mention of an entry that the actor cannot read gives no warning: the actor cannot know it.
  """
  @spec mentions(term(), String.t() | nil, Audience.t(), [{String.t(), String.t()}]) ::
          [String.t()]
  def mentions(actor, campaign_id, audience, mentions) do
    ids = for {kind, id} <- mentions, kind in @entry_kinds, do: id

    if ids == [] or is_nil(campaign_id) or not Audience.players_read?(audience) do
      []
    else
      Entry
      |> Ash.Query.filter(campaign_id == ^campaign_id and id in ^ids and hidden == true)
      |> Ash.Query.select([:id, :name])
      |> Ash.read!(actor: actor)
      |> Enum.sort_by(& &1.name)
      |> Enum.map(
        &("mentions the hidden entry #{inspect(&1.name)} (#{&1.id}), but players read this " <>
            "section: they see \"Restricted entry\" and learn that the entry exists. Remove the " <>
            "mention unless the GM asked for it")
      )
    end
  end
end
