defmodule Atlas.Search.Match do
  @moduledoc false

  def normalize(text) do
    text
    |> String.normalize(:nfkd)
    |> String.downcase()
    |> String.replace(~r/\p{M}/u, "")
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  def terms(text), do: text |> normalize() |> String.split() |> Enum.uniq()

  def matches?(text, term) do
    normalized = normalize(text)

    String.contains?(normalized, term) or
      Enum.any?(String.split(normalized), &similar?(&1, term))
  end

  defp similar?(word, term) do
    length = String.length(term)
    tolerance = if length >= 8, do: 2, else: 1

    length >= 4 and abs(String.length(word) - length) <= tolerance and
      distance(String.graphemes(word), String.graphemes(term)) <= tolerance
  end

  defp distance(left, right) do
    initial = Enum.to_list(0..length(right))

    left
    |> Enum.with_index(1)
    |> Enum.reduce(initial, fn {letter, row}, previous ->
      {cells, _diagonal, _above} =
        right
        |> Enum.zip(tl(previous))
        |> Enum.reduce({[row], hd(previous), row}, fn {other, above}, {cells, diagonal, before} ->
          cost = if letter == other, do: 0, else: 1
          cell = min(min(above + 1, before + 1), diagonal + cost)
          {[cell | cells], above, cell}
        end)

      Enum.reverse(cells)
    end)
    |> List.last()
  end
end
