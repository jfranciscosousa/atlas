defmodule Atlas.Mcp.Describe do
  @moduledoc """
  Generic-action implementation that reads one record as the actor and returns the listed fields
  and the plain text of the listed rich-text sections. The normal read policies and field policies
  apply, so a hidden section comes back as `nil`.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.RichText.PlainText

  @impl true
  def run(input, opts, context) do
    with {:ok, record} <- Ash.get(input.resource, input.arguments.id, actor: context.actor) do
      fields = Map.new(opts[:fields], &{&1, Map.fetch!(record, &1)})

      sections =
        Map.new(opts[:sections], fn section ->
          {section, text(Map.fetch!(record, Atlas.RichText.json_attribute(section)))}
        end)

      {:ok, Map.merge(fields, sections)}
    end
  end

  # A field policy replaces a hidden section with a `%Ash.ForbiddenField{}`.
  defp text(blocks) when is_list(blocks), do: PlainText.render(blocks)
  defp text(_hidden), do: nil
end
