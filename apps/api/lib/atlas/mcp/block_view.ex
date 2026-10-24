defmodule Atlas.Mcp.BlockView do
  @moduledoc """
  The blocks of a section as an MCP client reads them: the BlockNote JSON of the editor, with
  default props and empty styles left out, a read-only `label` on each mention, and a `hash`
  on each block. A client sends the hash back with an `update` to find out whether the block
  changed since it read it.

  Edits accept this form, so a client can send back what it read. `label` and `hash` are ignored.
  """

  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.PlainText

  @defaults %{
    "textColor" => "default",
    "backgroundColor" => "default",
    "textAlignment" => "left",
    "isToggleable" => false,
    "checked" => false
  }

  @doc """
  Reads stored blocks the way the editor state holds them, so that a hash from here equals a
  hash from the live document.
  """
  @spec normalize([map()]) :: [map()]
  def normalize([]), do: []

  def normalize(blocks) do
    case blocks |> Blocks.seed() |> Blocks.project() do
      {:ok, normalized} -> normalized
      _ -> blocks
    end
  end

  @doc "Changes with the own content of a block, not with its nested blocks."
  @spec hash(map()) :: String.t()
  def hash(block) do
    block
    |> Map.take(["type", "props", "content"])
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  @doc "The blocks for a client. `labels` are the names from `Atlas.RichText.Mentions.labels/3`."
  @spec render([map()], map()) :: [map()]
  def render(blocks, labels), do: blocks |> normalize() |> Enum.map(&block(&1, labels))

  @doc "One line per block: its ID, type, depth and the start of its text."
  @spec outline([map()], map()) :: [map()]
  def outline(blocks, labels) do
    opts = [labels: labels, links: false, at: false, images: true]

    blocks
    |> normalize()
    |> PlainText.flat(opts)
    |> Enum.map(fn entry ->
      %{id: entry.id, type: entry.type, depth: entry.depth, text: String.slice(entry.text, 0, 80)}
    end)
  end

  defp block(block, labels) do
    %{"id" => block["id"], "type" => block["type"], "hash" => hash(block)}
    |> put("props", props(block["props"]))
    |> put("content", content(block["content"], labels))
    |> put("children", Enum.map(block["children"] || [], &block(&1, labels)))
  end

  defp put(map, _key, empty) when empty in [nil, %{}, []], do: map
  defp put(map, key, value), do: Map.put(map, key, value)

  defp props(nil), do: nil
  defp props(props), do: Map.reject(props, fn {key, value} -> @defaults[key] == value end)

  defp content(%{"rows" => rows} = table, labels) do
    %{
      table
      | "rows" =>
          Enum.map(
            rows,
            &%{&1 | "cells" => Enum.map(&1["cells"], fn cell -> cell(cell, labels) end)}
          )
    }
  end

  defp content(nodes, labels) when is_list(nodes), do: Enum.map(nodes, &inline(&1, labels))
  defp content(nil, _labels), do: nil

  defp cell(%{"content" => nodes} = cell, labels) do
    cell
    |> Map.put("content", content(nodes, labels))
    |> Map.update("props", %{}, &props/1)
    |> Map.reject(fn {_key, value} -> value == %{} end)
  end

  defp inline(%{"type" => "text", "styles" => styles} = node, _labels) when styles == %{},
    do: Map.delete(node, "styles")

  defp inline(%{"type" => "link", "content" => nodes} = node, labels),
    do: %{node | "content" => content(nodes, labels)}

  defp inline(
         %{"type" => "mention", "props" => %{"kind" => kind, "id" => id} = props} = node,
         labels
       ),
       do: %{
         node
         | "props" => Map.put(props, "label", Map.get(labels, {kind, id}, "Restricted entry"))
       }

  defp inline(node, _labels), do: node
end
