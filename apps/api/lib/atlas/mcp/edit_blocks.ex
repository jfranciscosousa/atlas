defmodule Atlas.Mcp.EditBlocks do
  @moduledoc """
  Edits the blocks of one rich-text section by block ID, as the actor, like a person who works
  in the block editor. It implements `edit_blocks`: a list of `insert`, `update`, `delete` and
  `move` operations, applied in order as one edit. If one operation fails, nothing changes.

  The edit is a live edit, not a save: it becomes a Yjs update that goes through
  `Atlas.RichText.Collab.apply_update/4`, like an edit from an editor. The actor's rights are
  checked there, and everybody who has the section open sees the change at once. An `update`
  replaces the own content of one block and leaves its nested blocks alone.

  Two guards protect the layout. An edit that removes an image needs `remove_images`, and an edit
  that removes more than 10 blocks needs `delete_many`. Two warnings go back with the result
  and change nothing: an `update` that drops bold, links or mentions the block had, and an
  `update` that carries no `hash`, so a human's edit in the same block could be overwritten.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Mcp.BlockView
  alias Atlas.RichText.Collab
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document

  @max_operations 100
  @max_removed 10
  @op_keys %{
    "insert" => ~w(op after before parent blocks),
    "update" => ~w(op id type props content hash),
    "delete" => ~w(op id),
    "move" => ~w(op id after before parent)
  }
  @block_keys ~w(id type props content children hash)
  @no_content ~w(image divider)

  @impl true
  def run(input, _opts, %{actor: actor}) do
    args = input.arguments

    with {:ok, target} <- target("#{args.kind}:#{args.id}:#{args.section}"),
         {:ok, state} <- state(target, actor),
         {:ok, update, inserted, warnings} <- change(state, args),
         {:ok, result} <-
           Collab.apply_update(target, actor, update,
             expected_revision: Map.get(args, :expected_revision)
           ) do
      case result do
        {:changed, revision} ->
          Phoenix.PubSub.broadcast(Atlas.PubSub, Collab.topic(target), {:collab_update, update})
          {:ok, %{saved: true, revision: revision, inserted: inserted, warnings: warnings}}

        :unchanged ->
          {:ok, %{saved: false, revision: nil, inserted: inserted, warnings: warnings}}
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

  # Applies the operations to a copy of the stored state. The update holds only the difference.
  defp change(_state, %{operations: operations}) when length(operations) > @max_operations,
    do: {:error, "has more than #{@max_operations} operations: send fewer at a time"}

  defp change(state, args) do
    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state)
    {:ok, vector} = Yex.encode_state_vector(doc)

    with {:ok, before} <- Blocks.project(doc),
         {:ok, inserted, warnings} <- apply_all(doc, args.operations),
         {:ok, after_edit} <- Blocks.project(doc),
         :ok <- guard(before, after_edit, args),
         {:ok, update} <- Yex.encode_state_as_update(doc, vector) do
      {:ok, update, inserted, warnings}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, "the section has a shape that edits cannot change"}

      error ->
        error
    end
  end

  # Compares the section before and after the edit, whatever the operations were.
  defp guard(before, after_edit, args) do
    lost_images = Document.image_ids(before) -- Document.image_ids(after_edit)
    removed = Blocks.ids(before) -- Blocks.ids(after_edit)

    cond do
      lost_images != [] and not args.remove_images ->
        {:error,
         "would remove #{length(lost_images)} image(s): #{Enum.join(lost_images, ", ")}. " <>
           "An image is shared work: set remove_images to true only if you mean to remove it"}

      length(removed) > @max_removed and not args.delete_many ->
        {:error,
         "would delete #{length(removed)} blocks, more than #{@max_removed}. " <>
           "Set delete_many to true only if you mean to delete that many"}

      true ->
        :ok
    end
  end

  defp apply_all(doc, operations) do
    operations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], []}, fn {operation, index}, {:ok, inserted, warnings} ->
      case apply_one(doc, operation) do
        {:ok, ids, new} ->
          {:cont,
           {:ok, inserted ++ ids, warnings ++ Enum.map(new, &"operations[#{index}]: #{&1}")}}

        {:error, message} ->
          {:halt, {:error, "operations[#{index}]: #{message}"}}
      end
    end)
  end

  defp apply_one(doc, %{"op" => op} = operation) when is_map_key(@op_keys, op) do
    with :ok <- known_keys(operation, Map.fetch!(@op_keys, op)),
         {:ok, current} <- Blocks.project(doc) do
      run_op(op, doc, operation, current)
    else
      {:error, reason} when is_atom(reason) ->
        {:error, "the section has a shape that edits cannot change"}

      error ->
        error
    end
  end

  defp apply_one(_doc, %{"op" => op}),
    do: {:error, "op #{inspect(op)} is not known; use insert, update, delete or move"}

  defp apply_one(_doc, _operation), do: {:error, "needs an op: insert, update, delete or move"}

  defp run_op("insert", doc, operation, current) do
    with {:ok, position} <- position(operation),
         {:ok, blocks} <- new_blocks(operation["blocks"], current),
         :ok <- Blocks.insert(doc, position, blocks),
         :ok <- drop_blank(doc, position, current) do
      {:ok, Blocks.ids(blocks), []}
    end
  end

  defp run_op("update", doc, %{"id" => id} = operation, current) do
    with {:ok, block} <- Blocks.find(current, id),
         :ok <- unchanged(block, operation["hash"]),
         {:ok, changed} <- change_block(block, operation),
         :ok <- Blocks.set_content(doc, changed) do
      {:ok, [], warnings(block, changed, operation)}
    end
  end

  defp run_op("delete", doc, %{"id" => id}, _current) do
    with :ok <- Blocks.delete(doc, id), do: {:ok, [], []}
  end

  defp run_op("move", doc, %{"id" => id} = operation, _current) do
    with {:ok, position} <- position(operation),
         :ok <- positioned(position),
         :ok <- Blocks.move(doc, id, position) do
      {:ok, [], []}
    end
  end

  defp run_op(op, _doc, _operation, _current), do: {:error, "#{op} needs an id"}

  defp known_keys(operation, allowed) do
    case Map.keys(operation) -- allowed do
      [] -> :ok
      keys -> {:error, "has unknown keys #{inspect(keys)}; use #{Enum.join(allowed, ", ")}"}
    end
  end

  defp position(operation) do
    case Enum.filter(~w(after before parent), &Map.has_key?(operation, &1)) do
      [] -> {:ok, :end}
      [key] -> reference(key, operation[key])
      _ -> {:error, "use only one of after, before and parent"}
    end
  end

  defp reference(key, id) when is_binary(id) do
    {:ok, {%{"after" => :after, "before" => :before, "parent" => :into}[key], id}}
  end

  defp reference(key, _), do: {:error, "#{key} must be a block id"}

  defp positioned(:end), do: {:error, "move needs one of after, before and parent"}
  defp positioned(_), do: :ok

  # A section with no text is one empty paragraph. The first insert at the end replaces it.
  defp drop_blank(doc, :end, [%{"type" => "paragraph", "id" => id} = blank]) do
    if blank?(blank), do: Blocks.delete(doc, id), else: :ok
  end

  defp drop_blank(_doc, _position, _current), do: :ok

  defp blank?(block), do: block["content"] in [nil, []] and block["children"] in [nil, []]

  defp unchanged(_block, nil), do: :ok

  defp unchanged(block, hash) do
    if hash == BlockView.hash(block),
      do: :ok,
      else:
        {:error,
         "block #{inspect(block["id"])} was edited by someone since you read it, and this " <>
           "update would overwrite that edit: read it again with read_blocks, then retry"}
  end

  defp warnings(block, changed, operation) do
    lost = features(block["content"]) -- features(changed["content"])

    Enum.reject(
      [
        lost != [] &&
          "block #{inspect(block["id"])} lost #{Enum.join(lost, ", ")} that it had. If you did " <>
            "not mean that, update it again and keep them in content",
        is_nil(operation["hash"]) &&
          "update of block #{inspect(block["id"])} had no hash, so an edit that someone made in " <>
            "this block since you read it was overwritten without notice: send the hash from reading"
      ],
      &(&1 == false)
    )
  end

  # Bold, links and mentions are what a plain-text rewrite of a block silently drops.
  defp features(nodes) when is_list(nodes),
    do: nodes |> Enum.flat_map(&node_features/1) |> Enum.uniq()

  defp features(_), do: []

  defp node_features(%{"type" => "text", "styles" => styles}),
    do: for({style, value} <- styles, value not in [false, nil], do: style)

  defp node_features(%{"type" => "link", "content" => nodes}), do: ["link" | features(nodes)]
  defp node_features(%{"type" => "mention"}), do: ["mention"]
  defp node_features(_), do: []

  defp change_block(block, operation) do
    changed =
      block
      |> Map.put("type", operation["type"] || block["type"])
      |> Map.update("props", %{}, &Map.merge(&1, operation["props"] || %{}))
      |> then(fn changed ->
        if Map.has_key?(operation, "content"),
          do: Map.put(changed, "content", content(operation["content"])),
          else: changed
      end)

    with :ok <- check_all([changed]),
         {:ok, _} <- validate([Map.put(changed, "children", [])]) do
      {:ok, changed}
    end
  end

  defp new_blocks(blocks, current) when is_list(blocks) and blocks != [] do
    with {:ok, blocks} <- blocks |> Enum.map(&block/1) |> collect(),
         :ok <- check_all(blocks),
         {:ok, _} <- validate(blocks),
         :ok <- fresh_ids(blocks, current) do
      {:ok, blocks}
    end
  end

  defp new_blocks(_, _), do: {:error, "insert needs a list of blocks"}

  defp collect(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, block} -> block end)}
      error -> error
    end
  end

  defp validate(blocks) do
    case Document.cast_input(blocks, []) do
      {:ok, _} = ok -> ok
      {:error, message} -> {:error, message}
    end
  end

  defp fresh_ids(blocks, current) do
    ids = Blocks.ids(blocks)
    taken = Blocks.ids(current)

    cond do
      ids != Enum.uniq(ids) ->
        {:error, "two new blocks have the same id"}

      (clash = Enum.find(ids, &(&1 in taken))) != nil ->
        {:error, "block id #{inspect(clash)} exists: leave out id to get a new one"}

      true ->
        :ok
    end
  end

  defp check_all(blocks) do
    Enum.reduce_while(blocks, :ok, fn block, :ok ->
      with :ok <- check_content(block),
           :ok <- check_all(block["children"] || []) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp check_content(%{"type" => type} = block) when type in @no_content do
    if block["content"] in [nil, []],
      do: :ok,
      else: {:error, "a #{type} block has no content"}
  end

  defp check_content(_), do: :ok

  # Fills in what BlockNote defaults: ID, props, children and empty styles.
  defp block(%{} = block) do
    case Map.keys(block) -- @block_keys do
      [] ->
        with children when is_list(children) <- block["children"] || [],
             {:ok, children} <- children |> Enum.map(&block/1) |> collect() do
          {:ok,
           block
           |> Map.drop(["hash"])
           |> Map.put("id", block["id"] || Ash.UUID.generate())
           |> Map.put("props", block["props"] || %{})
           |> Map.put("children", children)
           |> put_content()}
        else
          {:error, _} = error -> error
          _ -> {:error, "block children must be a list"}
        end

      keys ->
        {:error, "a block has unknown keys #{inspect(keys)}; use #{Enum.join(@block_keys, ", ")}"}
    end
  end

  defp block(_), do: {:error, "a block must be an object with a type"}

  defp put_content(%{"content" => content} = block), do: %{block | "content" => content(content)}
  defp put_content(block), do: block

  # A string is one text node, as in BlockNote's own API. A mention drops its read-only label.
  defp content(text) when is_binary(text),
    do: [%{"type" => "text", "text" => text, "styles" => %{}}]

  defp content(%{"rows" => rows} = table) when is_list(rows),
    do: %{table | "rows" => Enum.map(rows, &row/1)}

  defp content(nodes) when is_list(nodes), do: Enum.map(nodes, &inline/1)
  defp content(other), do: other

  defp row(%{"cells" => cells} = row) when is_list(cells),
    do: %{row | "cells" => Enum.map(cells, &cell/1)}

  defp row(other), do: other

  defp cell(%{"content" => nodes} = cell), do: %{cell | "content" => content(nodes)}
  defp cell(nodes), do: content(nodes)

  defp inline(text) when is_binary(text), do: %{"type" => "text", "text" => text, "styles" => %{}}

  defp inline(%{"type" => "text"} = node), do: Map.put_new(node, "styles", %{})

  defp inline(%{"type" => "link", "content" => nodes} = node) when is_list(nodes),
    do: %{node | "content" => content(nodes)}

  defp inline(%{"type" => "mention", "props" => %{} = props} = node),
    do: %{node | "props" => Map.take(props, ["kind", "id"])}

  defp inline(other), do: other

  defp invalid(:forbidden), do: error("is not a section that exists and that you may write")
  defp invalid(:stale), do: error("changed since you read it: read it again, then retry")
  defp invalid(:update_too_large), do: error("is too long to write at once")
  defp invalid(:document_too_large), do: error("would make the section too large")
  defp invalid({:rejected, reason}), do: error("is not valid: #{inspect(reason)}")
  defp invalid(message) when is_binary(message), do: error(message)
  defp invalid(_), do: error("could not be written")

  defp error(message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: :operations, message: message)
end
