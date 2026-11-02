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

  alias Atlas.Mcp.{BlockView, Records}

  @impl true
  def run(input, opts, context) do
    with {:ok, record} <-
           Ash.get(input.resource, input.arguments.id,
             actor: context.actor,
             load: Keyword.get(opts, :load, [])
           ) do
      {:ok, hd(describe([record], opts, context.actor))}
    end
  end

  @doc """
  Describes records that were read as the actor, in the order of the records. Mentions are named
  once for each campaign, however many records it has, so the number of queries does not grow
  with the number of records.
  """
  @spec describe([struct()], keyword(), term()) :: [map()]
  def describe(records, opts, actor) do
    campaign_ids = Records.campaign_ids(records)

    # The names of mentions are read as the actor, so a restricted entry stays nameless.
    labels =
      records
      |> Enum.zip(campaign_ids)
      |> Enum.map(fn {record, campaign_id} -> {campaign_id, documents(record, opts)} end)
      |> Records.labels(actor)

    records
    |> Enum.zip(campaign_ids)
    |> Enum.map(fn {record, campaign_id} ->
      render(record, opts, Map.fetch!(labels, campaign_id))
    end)
  end

  defp documents(record, opts) do
    opts[:sections]
    |> Enum.map(&Map.fetch!(record, Atlas.RichText.json_attribute(&1)))
    |> Enum.filter(&is_list/1)
  end

  defp render(record, opts, labels) do
    fields = Map.new(opts[:fields], &{&1, field(Map.fetch!(record, &1))})
    markdown = Keyword.get(opts, :markdown, [])

    sections =
      Map.new(opts[:sections], fn section ->
        blocks = Map.fetch!(record, Atlas.RichText.json_attribute(section))
        {section, view(blocks, labels, section in markdown)}
      end)

    revisions =
      Map.new(opts[:sections], fn section ->
        {:"#{section}_revision",
         field(Map.fetch!(record, Atlas.RichText.revision_attribute(section)))}
      end)

    fields
    |> Map.merge(sections)
    |> Map.merge(revisions)
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
