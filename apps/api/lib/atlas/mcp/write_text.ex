defmodule Atlas.Mcp.WriteText do
  @moduledoc """
  Writes Markdown into one rich-text section, as the actor. It implements `write_text`, which
  replaces or appends, and `edit_text`, which changes one block and leaves the others alone.

  The write is a live edit, not a save: it becomes a Yjs update that goes through
  `Atlas.RichText.Collab.apply_update/4`, like an edit from an editor. The actor's rights are
  checked there, and everybody who has the section open sees the change at once.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.RichText.Collab
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document
  alias Atlas.RichText.Markdown

  @impl true
  def run(input, _opts, %{actor: actor}) do
    args = input.arguments

    with {:ok, target} <- target("#{args.kind}:#{args.id}:#{args.section}"),
         {:ok, state} <- state(target, actor),
         {:ok, update} <- update(state, input.action.name, args),
         {:ok, result} <-
           Collab.apply_update(target, actor, update,
             expected_revision: Map.get(args, :expected_revision)
           ) do
      case result do
        {:changed, revision} ->
          Phoenix.PubSub.broadcast(Atlas.PubSub, Collab.topic(target), {:collab_update, update})
          {:ok, %{saved: true, revision: revision}}

        :unchanged ->
          {:ok, %{saved: false, revision: nil}}
      end
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

  defp update(state, :write_text, args) do
    blocks = Markdown.parse(args.markdown)

    with {:ok, _} <- Document.cast_input(blocks, []) do
      change(state, fn doc, current ->
        if args.mode == :append and not Enum.all?(current, &blank?/1) do
          Blocks.append(doc, blocks)
        else
          with :ok <- keeps_images(args, current, blocks), do: Blocks.replace(doc, blocks)
        end
      end)
    end
  end

  defp update(state, :edit_text, %{find: find, replace: replace}) do
    change(state, fn doc, current ->
      # A mention reads back with its current name, so the match ignores names.
      texts = current |> Markdown.render_each() |> Enum.map(&unlabel/1)
      find = unlabel(find)
      matches = Enum.sum(for text <- texts, do: length(:binary.matches(text, find)))

      with :ok <- single_match(matches),
           index = Enum.find_index(texts, &String.contains?(&1, find)),
           :ok <- markdown_safe(Enum.at(current, index)),
           blocks = texts |> Enum.at(index) |> String.replace(find, replace) |> Markdown.parse(),
           {:ok, _} <- Document.cast_input(blocks, []) do
        Blocks.replace_at(doc, index, blocks)
      end
    end)
  end

  # Returns the update that `fun` makes on a copy of the stored state.
  defp change(state, fun) do
    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state)
    {:ok, vector} = Yex.encode_state_vector(doc)
    {:ok, current} = Blocks.project(doc)

    with :ok <- fun.(doc, current), do: Yex.encode_state_as_update(doc, vector)
  end

  # An empty section is one empty paragraph, which an append replaces.
  defp blank?(%{"type" => "paragraph"} = block),
    do: block["content"] in [nil, []] and block["children"] in [nil, []]

  defp blank?(_), do: false

  defp keeps_images(%{remove_images: true}, _current, _blocks), do: :ok

  defp keeps_images(_args, current, blocks) do
    case Document.image_ids(current) -- Document.image_ids(blocks) do
      [] ->
        :ok

      lost ->
        {:error,
         "would remove #{length(lost)} image(s): #{Enum.join(lost, ", ")}. " <>
           "Keep each as a ![](atlas-image:ID) line, or set remove_images to true"}
    end
  end

  # Editing goes through Markdown, so a block that Markdown cannot carry would lose formatting.
  defp markdown_safe(block) do
    again = [block] |> Markdown.render_each() |> Enum.join("\n") |> Markdown.parse()

    if strip_ids(again) == strip_ids([block]),
      do: :ok,
      else:
        {:error,
         "this block has formatting that Markdown cannot keep (underline, colors or alignment)"}
  end

  defp strip_ids(blocks),
    do:
      Enum.map(
        blocks,
        &(&1 |> Map.delete("id") |> Map.update("children", [], fn c -> strip_ids(c) end))
      )

  defp unlabel(text), do: String.replace(text, ~r/\[@[^\]]*\]\(atlas-entry:/, "[@](atlas-entry:")

  defp single_match(1), do: :ok

  defp single_match(0),
    do: {:error, "has no block with that find text, exactly as get_* shows it"}

  defp single_match(_), do: {:error, "has that find text more than once: add more context"}

  defp invalid(:forbidden), do: error("is not a section that exists and that you may write")
  defp invalid(:stale), do: error("changed since you read it: read it again, then retry")
  defp invalid(:update_too_large), do: error("is too long to write at once")
  defp invalid(:document_too_large), do: error("would make the section too large")
  defp invalid({:rejected, reason}), do: error("is not valid: #{inspect(reason)}")
  defp invalid(message) when is_binary(message), do: error(message)
  defp invalid(_), do: error("could not be written")

  defp error(message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: :id, message: message)
end
