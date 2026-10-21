defmodule Atlas.RichText.Collab.AwarenessTest do
  use ExUnit.Case, async: true

  alias Atlas.RichText.Collab.Awareness

  # As y-prosemirror writes it: a field that does not apply is null.
  @position %{
    "type" => %{"client" => 7, "clock" => 3},
    "tname" => nil,
    "item" => nil,
    "assoc" => 0
  }
  @cursor %{"anchor" => @position, "head" => @position}

  # A frame as a browser writes it: the awareness update is length-prefixed.
  defp frame(id, clock, state) do
    json = Jason.encode!(state)

    update =
      <<1, varuint(id)::binary, varuint(clock)::binary, varuint(byte_size(json))::binary,
        json::binary>>

    <<1, varuint(byte_size(update))::binary, update::binary>>
  end

  defp varuint(value) when value < 0x80, do: <<value>>
  defp varuint(value), do: <<0x80 + rem(value, 0x80), varuint(div(value, 0x80))::binary>>

  describe "the wire format" do
    test "reads the example of the y-protocols documentation" do
      update = <<1, 210, 165, 202, 167, 8, 1, 2, 123, 125>>

      assert {:ok, [{2_230_489_810, 1, %{}}]} =
               Awareness.decode_frame(<<1, byte_size(update), update::binary>>)
    end

    test "a frame the server writes is read by Yex and by this module" do
      state = %{"user" => %{"name" => "Ann"}, "cursor" => @cursor}
      frame = Awareness.encode_frame(4_000_000_000, 300, state)

      assert {:ok, [{4_000_000_000, 300, ^state}]} = Awareness.decode_frame(frame)

      {:ok, awareness} = Yex.Awareness.new(Yex.Doc.new())
      {:ok, {:awareness, update}} = Yex.Sync.message_decode(frame)
      :ok = Yex.Awareness.apply_update(awareness, update)

      assert %{4_000_000_000 => %{"user" => %{"name" => "Ann"}, "cursor" => %{"head" => _}}} =
               Yex.Awareness.get_states(awareness)
    end

    test "a removal is a null state" do
      assert {:ok, [{9, 5, nil}]} = Awareness.decode_frame(Awareness.encode_frame(9, 5, nil))
    end

    test "bytes that are not a frame give an error" do
      for bad <- [
            <<>>,
            <<0, 1, 2>>,
            <<1>>,
            <<1, 200, 1>>,
            <<1, 3, 1, 1, 1>>,
            <<1, 2, 0, 0>>,
            # a number that never ends
            <<1, 11, 1, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1>>,
            # text that is not JSON
            <<1, 6, 1, 1, 1, 2, 123, 123>>,
            # bytes after the last client
            <<1, 7, 1, 1, 1, 2, 123, 125, 0>>
          ] do
        assert :error = Awareness.decode_frame(bad)
      end
    end
  end

  describe "the cursor of a browser" do
    test "a valid cursor is returned, whatever else the browser sends" do
      state = %{
        "user" => %{"name" => "Admin", "color" => "#000", "email" => "root@example.com"},
        "cursor" => @cursor,
        "extra" => "x"
      }

      assert {:ok, @cursor} = Awareness.client_cursor(frame(123, 1, state))
    end

    test "no cursor and a null cursor mean no cursor" do
      assert {:ok, nil} = Awareness.client_cursor(frame(1, 1, %{"user" => %{}}))
      assert {:ok, nil} = Awareness.client_cursor(frame(1, 1, %{"cursor" => nil}))
    end

    test "a removal alone holds nothing to relay; a removal beside a state is skipped" do
      assert :none = Awareness.client_cursor(Awareness.encode_frame(1, 2, nil))

      json = Jason.encode!(%{"cursor" => @cursor})
      update = <<2, 5, 9, 4, "null", 1, 1, varuint(byte_size(json))::binary, json::binary>>

      assert {:ok, @cursor} =
               Awareness.client_cursor(<<1, varuint(byte_size(update))::binary, update::binary>>)
    end

    test "two states in one frame are refused" do
      json = Jason.encode!(%{"cursor" => @cursor})
      entry = <<1, 1, varuint(byte_size(json))::binary, json::binary>>
      update = <<2, entry::binary, entry::binary>>

      assert :error =
               Awareness.client_cursor(<<1, varuint(byte_size(update))::binary, update::binary>>)
    end

    test "a cursor with the wrong shape is refused" do
      position = @position

      for cursor <- [
            "text",
            [],
            %{},
            %{"anchor" => position},
            %{"anchor" => position, "head" => position, "extra" => 1},
            %{"anchor" => position, "head" => Map.put(position, "extra", 1)},
            %{"anchor" => position, "head" => Map.delete(position, "assoc")},
            %{"anchor" => position, "head" => %{"assoc" => 0}},
            %{"anchor" => position, "head" => %{"assoc" => 0, "type" => nil, "item" => nil}},
            %{"anchor" => position, "head" => Map.put(position, "assoc", "0")},
            %{"anchor" => position, "head" => Map.put(position, "assoc", 1.5)},
            %{
              "anchor" => position,
              "head" => Map.put(position, "type", %{"client" => -1, "clock" => 1})
            },
            %{"anchor" => position, "head" => Map.put(position, "type", %{"client" => 1})},
            %{
              "anchor" => position,
              "head" => Map.put(position, "type", %{"client" => "1", "clock" => 1})
            },
            %{
              "anchor" => position,
              "head" => Map.put(position, "item", %{"client" => 1, "clock" => 1, "x" => 1})
            },
            %{"anchor" => position, "head" => Map.put(position, "tname", 5)},
            %{
              "anchor" => position,
              "head" => Map.put(position, "tname", String.duplicate("a", 101))
            }
          ] do
        assert :error = Awareness.client_cursor(frame(1, 1, %{"cursor" => cursor})),
               inspect(cursor)
      end
    end

    test "a state that is not a map is refused" do
      for state <- ["text", 5, [1], true] do
        assert :error = Awareness.client_cursor(frame(1, 1, state))
      end
    end

    test "a frame over 2 KB is refused" do
      state = %{"cursor" => nil, "pad" => String.duplicate("a", 2_100)}
      assert :error = Awareness.client_cursor(frame(1, 1, state))
    end

    test "the largest valid cursor stays under 500 bytes" do
      position = Map.put(@position, "tname", String.duplicate("a", 100))

      big =
        Map.put(position, "item", %{
          "client" => 9_007_199_254_740_991,
          "clock" => 9_007_199_254_740_991
        })

      cursor = %{"anchor" => big, "head" => big}
      assert {:ok, ^cursor} = Awareness.client_cursor(frame(1, 1, %{"cursor" => cursor}))
      assert byte_size(Jason.encode!(cursor)) < 500
    end
  end
end
