defmodule Atlas.RichText.Collab.Awareness do
  @moduledoc """
  The Yjs awareness wire format (y-protocols), reduced to what live editing allows.

  A frame is the byte `1`, then a length-prefixed update. An update is a count, then for each
  client: its ID, its clock, and its state as length-prefixed JSON (`null` means gone).

  A browser may send only the position of its cursor. `client_cursor/1` reads a frame from a
  browser and returns that position, checked field by field. Everything else in the frame
  (names, colours, IDs, clocks) is ignored: the server sets those itself. `encode_frame/3` writes
  the frames the server sends.
  """

  @max_frame 2_048
  @max_entries 16
  @max_name_bytes 100
  @max_int 9_007_199_254_740_991

  @doc "The largest frame a browser may send, in bytes."
  def max_frame, do: @max_frame

  @doc """
  The cursor a browser frame carries: `{:ok, cursor}` (a map, or `nil` for "no cursor"),
  `:none` when the frame holds no state to relay, or `:error` for a frame that is not valid.
  """
  @spec client_cursor(binary()) :: {:ok, map() | nil} | :none | :error
  def client_cursor(frame) when byte_size(frame) <= @max_frame do
    with {:ok, entries} <- decode_frame(frame) do
      # The browser sends its own state. A removal of another client can come with it: skip it.
      case Enum.reject(entries, fn {_id, _clock, state} -> is_nil(state) end) do
        [] -> :none
        [{_id, _clock, state}] -> cursor(state)
        _more -> :error
      end
    end
  end

  def client_cursor(_frame), do: :error

  @doc "Reads the entries of an awareness frame: `[{client_id, clock, state}]`."
  @spec decode_frame(binary()) :: {:ok, [{non_neg_integer(), non_neg_integer(), term()}]} | :error
  def decode_frame(<<1, rest::binary>>) do
    with {:ok, update, <<>>} <- read_bytes(rest),
         {:ok, count, entries} <- read_varuint(update),
         true <- count <= @max_entries,
         {:ok, list} <- read_entries(entries, count, []) do
      {:ok, list}
    else
      _ -> :error
    end
  end

  def decode_frame(_), do: :error

  @doc "Writes a frame for one client. A `nil` state removes the client."
  @spec encode_frame(non_neg_integer(), non_neg_integer(), map() | nil) :: binary()
  def encode_frame(client_id, clock, state) do
    update = varuint(1) <> varuint(client_id) <> varuint(clock) <> bytes(Jason.encode!(state))
    <<1>> <> bytes(update)
  end

  defp cursor(%{} = state) do
    case Map.get(state, "cursor") do
      nil -> {:ok, nil}
      cursor -> if valid_cursor?(cursor), do: {:ok, cursor}, else: :error
    end
  end

  defp cursor(_), do: :error

  defp valid_cursor?(%{"anchor" => anchor, "head" => head} = cursor) when map_size(cursor) == 2 do
    position?(anchor) and position?(head)
  end

  defp valid_cursor?(_), do: false

  # A Yjs relative position as JSON: `type` and `item` are IDs, `tname` a root name. A field that
  # does not apply is `null`. The shape bounds the size: a cursor never exceeds 500 bytes.
  defp position?(%{"assoc" => assoc} = position) do
    is_integer(assoc) and abs(assoc) <= 1_000 and
      Enum.all?(position, fn
        {"assoc", _} ->
          true

        {"tname", name} ->
          is_nil(name) or (is_binary(name) and byte_size(name) <= @max_name_bytes)

        {key, id} when key in ["type", "item"] ->
          is_nil(id) or id?(id)

        _ ->
          false
      end) and Enum.any?(["type", "item", "tname"], &(not is_nil(position[&1])))
  end

  defp position?(_), do: false

  defp id?(%{"client" => client, "clock" => clock} = id) when map_size(id) == 2,
    do: int?(client) and int?(clock)

  defp id?(_), do: false

  defp int?(value), do: is_integer(value) and value >= 0 and value <= @max_int

  defp read_entries(<<>>, 0, acc), do: {:ok, Enum.reverse(acc)}
  defp read_entries(_rest, 0, _acc), do: :error

  defp read_entries(binary, count, acc) do
    with {:ok, id, binary} <- read_varuint(binary),
         {:ok, clock, binary} <- read_varuint(binary),
         {:ok, json, binary} <- read_bytes(binary),
         {:ok, state} <- Jason.decode(json) do
      read_entries(binary, count - 1, [{id, clock, state} | acc])
    else
      _ -> :error
    end
  end

  defp read_bytes(binary) do
    with {:ok, size, rest} <- read_varuint(binary),
         <<chunk::binary-size(^size), rest::binary>> <- rest do
      {:ok, chunk, rest}
    else
      _ -> :error
    end
  end

  # Little-endian base 128. Seven bytes hold 49 bits, enough for the IDs and clocks browsers use.
  defp read_varuint(binary, shift \\ 0, acc \\ 0)
  defp read_varuint(_binary, shift, _acc) when shift > 42, do: :error

  defp read_varuint(<<byte, rest::binary>>, shift, acc) do
    acc = acc + Bitwise.bsl(Bitwise.band(byte, 0x7F), shift)
    if byte < 0x80, do: {:ok, acc, rest}, else: read_varuint(rest, shift + 7, acc)
  end

  defp read_varuint(<<>>, _shift, _acc), do: :error

  defp bytes(binary), do: varuint(byte_size(binary)) <> binary

  defp varuint(value) when value < 0x80, do: <<value>>

  defp varuint(value),
    do: <<Bitwise.bor(0x80, Bitwise.band(value, 0x7F)), varuint(Bitwise.bsr(value, 7))::binary>>
end
