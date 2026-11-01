defmodule Atlas.Mcp.Describe do
  @moduledoc """
  Generic-action implementation that reads one record as the actor and returns the listed fields
  and the blocks of the listed rich-text sections, in the form `edit_blocks` takes (see
  `Atlas.Mcp.BlockView`). Each section also has a `<section>_revision`, for the
  `expected_revision` of a write. The normal read policies and field policies apply, so a hidden
  section and its revision come back as `nil`.

  A section listed in `:markdown` comes back as Markdown text instead of blocks, for a text that
  an agent follows and never edits (see `Atlas.RichText.Markdown`).
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Mcp.BlockView
  alias Atlas.RichText.Mentions

  @impl true
  def run(input, opts, context) do
    with {:ok, record} <-
           Ash.get(input.resource, input.arguments.id,
             actor: context.actor,
             load: Keyword.get(opts, :load, [])
           ) do
      fields = Map.new(opts[:fields], &{&1, field(Map.fetch!(record, &1))})

      documents =
        Map.new(opts[:sections], fn section ->
          {section, Map.fetch!(record, Atlas.RichText.json_attribute(section))}
        end)

      # The names of mentions are read as the actor, so a restricted entry stays nameless.
      labels =
        documents
        |> Map.values()
        |> Enum.filter(&is_list/1)
        |> Mentions.labels(context.actor, campaign_id(record))

      markdown = Keyword.get(opts, :markdown, [])

      sections =
        Map.new(documents, fn {section, blocks} ->
          {section, view(blocks, labels, section in markdown)}
        end)

      revisions =
        Map.new(opts[:sections], fn section ->
          {:"#{section}_revision",
           field(Map.fetch!(record, Atlas.RichText.revision_attribute(section)))}
        end)

      {:ok,
       fields
       |> Map.merge(sections)
       |> Map.merge(revisions)}
    end
  end

  @doc "The ID of the campaign that a record belongs to. A skill belongs to none."
  def campaign_id(%Atlas.Campaigns.Campaign{id: id}), do: id
  def campaign_id(%Atlas.Content.Skill{}), do: nil
  def campaign_id(%{campaign_id: id}), do: id

  def campaign_id(%Atlas.Campaigns.PlayerLog{session_id: session_id}),
    do: Ash.get!(Atlas.Campaigns.Session, session_id, authorize?: false).campaign_id

  # A field policy replaces a hidden value with a `%Ash.ForbiddenField{}`.
  defp field(%Ash.ForbiddenField{}), do: nil
  defp field(value), do: value

  # A field policy replaces a hidden section with a `%Ash.ForbiddenField{}`.
  defp view(blocks, _labels, true) when is_list(blocks),
    do: Atlas.RichText.Markdown.render(blocks)

  defp view(blocks, labels, false) when is_list(blocks), do: BlockView.render(blocks, labels)
  defp view(_hidden, _labels, _markdown?), do: nil
end
