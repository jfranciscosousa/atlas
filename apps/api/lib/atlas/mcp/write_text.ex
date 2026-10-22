defmodule Atlas.Mcp.WriteText do
  @moduledoc """
  Writes Markdown into one rich-text section, as the actor.

  The write is a live edit, not a save: it becomes a Yjs update that goes through
  `Atlas.RichText.Collab.apply_update/3`, like an edit from an editor. The actor's rights are
  checked there, and everybody who has the section open sees the change at once.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.RichText.Collab
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document
  alias Atlas.RichText.Markdown

  @impl true
  def run(input, _opts, %{actor: actor}) do
    %{kind: kind, id: id, section: section, markdown: markdown, mode: mode} = input.arguments
    blocks = Markdown.parse(markdown)

    with {:ok, target} <- target("#{kind}:#{id}:#{section}"),
         {:ok, _} <- Document.cast_input(blocks, []),
         {:ok, state} <- state(target, actor),
         {:ok, update} <- update(state, blocks, mode),
         {:ok, result} <- Collab.apply_update(target, actor, update) do
      if result == :changed,
        do: Phoenix.PubSub.broadcast(Atlas.PubSub, Collab.topic(target), {:collab_update, update})

      {:ok, %{saved: result == :changed}}
    else
      {:error, reason} -> {:error, invalid(reason)}
    end
  end

  defp target(ref) do
    case Collab.parse(ref) do
      {:ok, target} -> {:ok, target}
      :error -> {:error, "has no such section"}
    end
  end

  # The first read after another writer changed the JSON only rebuilds the state.
  defp state(target, actor) do
    case Collab.read_state(target, actor) do
      {:ok, :reset} -> state(target, actor)
      other -> other
    end
  end

  defp update(state, blocks, mode) do
    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state)
    {:ok, vector} = Yex.encode_state_vector(doc)
    {:ok, current} = Blocks.project(doc)

    if mode == :append and not Enum.all?(current, &blank?/1),
      do: Blocks.append(doc, blocks),
      else: Blocks.replace(doc, blocks)

    Yex.encode_state_as_update(doc, vector)
  end

  # An empty section is one empty paragraph, which an append replaces.
  defp blank?(%{"type" => "paragraph"} = block),
    do: block["content"] in [nil, []] and block["children"] in [nil, []]

  defp blank?(_), do: false

  defp invalid(:forbidden), do: error("is not a section that exists and that you may write")
  defp invalid(:update_too_large), do: error("is too long to write at once")
  defp invalid(:document_too_large), do: error("would make the section too large")
  defp invalid({:rejected, reason}), do: error("is not valid: #{inspect(reason)}")
  defp invalid(message) when is_binary(message), do: error(message)
  defp invalid(_), do: error("could not be written")

  defp error(message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: :id, message: message)
end
