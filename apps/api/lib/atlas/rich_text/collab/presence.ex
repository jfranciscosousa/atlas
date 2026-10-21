defmodule Atlas.RichText.Collab.Presence do
  @moduledoc """
  What the server tells editors about the people who have a section open.

  The server decides each person's identity: the display name of the account (never the email)
  and a colour taken from a fixed palette by a hash of the user ID. `key` is a hash of the user ID.
  It lets a browser count one person once when they have two tabs open. It does not reveal the ID.
  """

  @palette ~w(#e11d48 #ea580c #ca8a04 #16a34a #0d9488 #0284c7 #4f46e5 #9333ea #c026d3 #78716c)
  @max_name 40
  @rate 20
  @window_ms 1_000

  @doc "The fixed colours, in order."
  def palette, do: @palette

  @doc "The colour of a user. The same ID always gives the same colour."
  def color(user_id), do: Enum.at(@palette, :erlang.phash2(to_string(user_id), length(@palette)))

  @doc "The identity the server shows for a user."
  @spec identity(%{id: term(), display_name: String.t()}) :: map()
  def identity(%{id: id, display_name: display_name}) do
    key =
      :crypto.hash(:sha256, to_string(id))
      |> binary_part(0, 8)
      |> Base.url_encode64(padding: false)

    %{"key" => key, "name" => name(display_name), "color" => color(id)}
  end

  @doc "The awareness state the server sends: the identity, and the cursor if there is one."
  @spec state(map(), map() | nil) :: map()
  def state(user, nil), do: %{"user" => identity(user)}
  def state(user, cursor), do: %{"user" => identity(user), "cursor" => cursor}

  defp name(display_name) do
    case display_name |> to_string() |> String.trim() |> String.slice(0, @max_name) do
      "" -> "Someone"
      name -> name
    end
  end

  @doc """
  Counts one awareness frame in a window of one second. Returns `{:ok, window}`, or `:limit`
  when the channel already sent 20 frames in this window.
  """
  @spec take({integer(), non_neg_integer()}, integer()) ::
          {:ok, {integer(), non_neg_integer()}} | :limit
  def take({started, count}, now) when now - started < @window_ms do
    if count < @rate, do: {:ok, {started, count + 1}}, else: :limit
  end

  def take(_window, now), do: {:ok, {now, 1}}
end
