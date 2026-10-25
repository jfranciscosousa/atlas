defmodule Atlas.Mcp.Describe do
  @moduledoc """
  Generic-action implementation that reads one record as the actor and returns the listed fields
  and the blocks of the listed rich-text sections, in the form `edit_blocks` takes (see
  `Atlas.Mcp.BlockView`). Each section also has a `<section>_revision`, for the
  `expected_revision` of a write. The normal read policies and field policies apply, so a hidden
  section and its revision come back as `nil`. The option `extra` names a `{module, function}` that
  gets the record and the actor and returns more data to merge into the result.
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

      sections = Map.new(documents, fn {section, blocks} -> {section, view(blocks, labels)} end)

      revisions =
        Map.new(opts[:sections], fn section ->
          {:"#{section}_revision",
           field(Map.fetch!(record, Atlas.RichText.revision_attribute(section)))}
        end)

      {:ok,
       fields
       |> Map.merge(sections)
       |> Map.merge(revisions)
       |> Map.merge(extra(record, opts, context))}
    end
  end

  # `extra: {module, function}` adds data that no attribute holds, such as the relations of an entry.
  defp extra(record, opts, context) do
    case Keyword.get(opts, :extra) do
      {module, function} -> apply(module, function, [record, context.actor])
      nil -> %{}
    end
  end

  @doc "The ID of the campaign that a record belongs to."
  def campaign_id(%Atlas.Campaigns.Campaign{id: id}), do: id
  def campaign_id(%{campaign_id: id}), do: id

  def campaign_id(%Atlas.Campaigns.PlayerLog{session_id: session_id}),
    do: Ash.get!(Atlas.Campaigns.Session, session_id, authorize?: false).campaign_id

  # A field policy replaces a hidden value with a `%Ash.ForbiddenField{}`.
  defp field(%Ash.ForbiddenField{}), do: nil
  defp field(value), do: value

  # A field policy replaces a hidden section with a `%Ash.ForbiddenField{}`.
  defp view(blocks, labels) when is_list(blocks), do: BlockView.render(blocks, labels)
  defp view(_hidden, _labels), do: nil
end
