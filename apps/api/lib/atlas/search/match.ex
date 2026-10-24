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

  # A chunk is a run of letters and digits that punctuation joins without a space: M.A.77, in-world.
  @chunk ~r/[\p{L}\p{N}]+(?:[^\s\p{L}\p{N}]+[\p{L}\p{N}]+)*/u
  @word ~r/[\p{L}\p{N}]+/u

  @doc """
  The words that an indexed text can answer. Punctuation splits a chunk into words, and the chunk
  also counts as one joined word, so the text "M.A.77" answers "m", "a", "77" and "ma77".
  """
  def terms(text) do
    text
    |> chunks()
    |> Enum.flat_map(fn chunk ->
      parts = words(chunk)
      if match?([_, _ | _], parts), do: parts ++ [Enum.join(parts)], else: parts
    end)
    |> Enum.uniq()
  end

  @doc """
  The words that a query asks for. A chunk is one word with its punctuation removed, so the query
  "M.A.77" asks for "ma77" and never for the letters "m" and "a" alone.
  """
  def query_terms(text) do
    text
    |> chunks()
    |> Enum.map(&(&1 |> words() |> Enum.join()))
    |> Enum.uniq()
  end

  defp chunks(text) do
    text
    |> String.normalize(:nfkd)
    |> String.downcase()
    |> String.replace(~r/\p{M}/u, "")
    |> then(&Regex.scan(@chunk, &1))
    |> List.flatten()
  end

  defp words(chunk), do: @word |> Regex.scan(chunk) |> List.flatten()

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
