defmodule Atlas.Mcp.Describe do
  @moduledoc """
  Generic-action implementation that reads one record as the actor and returns the listed fields
  and the plain text of the listed rich-text sections. The normal read policies and field policies
  apply, so a hidden section comes back as `nil`.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.RichText.{Mentions, PlainText}

  @impl true
  def run(input, opts, context) do
    with {:ok, record} <- Ash.get(input.resource, input.arguments.id, actor: context.actor) do
      fields = Map.new(opts[:fields], &{&1, Map.fetch!(record, &1)})

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

      sections = Map.new(documents, fn {section, blocks} -> {section, text(blocks, labels)} end)

      {:ok, Map.merge(fields, sections)}
    end
  end

  defp campaign_id(%Atlas.Campaigns.Campaign{id: id}), do: id
  defp campaign_id(%{campaign_id: id}), do: id

  defp campaign_id(%Atlas.Campaigns.PlayerLog{session_id: session_id}),
    do: Ash.get!(Atlas.Campaigns.Session, session_id, authorize?: false).campaign_id

  # A field policy replaces a hidden section with a `%Ash.ForbiddenField{}`.
  defp text(blocks, labels) when is_list(blocks), do: PlainText.render(blocks, labels: labels)
  defp text(_hidden, _labels), do: nil
end
