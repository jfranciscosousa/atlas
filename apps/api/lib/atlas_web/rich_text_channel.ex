defmodule AtlasWeb.RichTextChannel do
  @moduledoc """
  One editor's connection to one rich-text section: `doc:<kind>:<id>:<section>`.

  The channel speaks the Yjs sync protocol. It trusts nothing it learned earlier: before it
  handles each client frame and before it delivers each update, it checks the signed-in session
  and the user's rights on the section again (`Atlas.RichText.Collab.authorize/2`). A user who
  lost access gets one `revoked` message and the channel closes. A user who lost only the right
  to write gets a `permissions` message and the channel turns read-only.

  A frame that carries an update gets a reply after the server handled it: `ok` when the server
  stored the update or it added nothing, `error` when the server refused it. The browser shows
  "Saved" only after an `ok` reply.

  Presence: every channel shows the people who have the section open, readers included. The
  server decides who each person is. A browser may send only its cursor, in an awareness frame.
  The server checks the cursor (`Collab.Awareness`), gives the channel its own awareness client ID
  (a browser cannot speak for another channel), and sends the cursor together with the name and
  colour of the signed-in user. A new channel asks the others for their state. A channel that ends
  tells the others to remove its client ID. A channel accepts at most 20 awareness frames per
  second, of at most 2 KB each. It drops all others without a reply.

  Shortcut: a channel that is killed without cleanup sends no removal. The others drop it when
  its heartbeat (every 10 s) stops, 30 s later, because browsers expire silent awareness states.
  """
  use Phoenix.Channel

  alias Atlas.RichText.Collab
  alias Atlas.RichText.Collab.Awareness
  alias Atlas.RichText.Collab.Presence

  @heartbeat_ms 10_000

  @impl true
  def join("doc:" <> ref, _params, socket) do
    with {:ok, target} <- Collab.parse(ref),
         {:ok, socket} <- check(assign(socket, :target, target)),
         {:ok, %{epoch: epoch}} <- Collab.open(target, socket.assigns.user) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(target))
      send(self(), :join_presence)

      socket =
        assign(socket,
          # Starts at 1: a browser ignores a state whose clock is not above the one it knows (0).
          awareness: %{
            id: :binary.decode_unsigned(:crypto.strong_rand_bytes(4)),
            clock: 1,
            cursor: nil,
            window: {System.monotonic_time(:millisecond), 0}
          }
        )

      reply = %{
        canWrite: socket.assigns.can_write?,
        epoch: epoch,
        key: Presence.identity(socket.assigns.user)["key"]
      }

      {:ok, reply, socket}
    else
      # The section exists and the user may open it, but the server cannot build its document.
      {:error, {:rejected, _}} -> {:error, %{reason: "unavailable"}}
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_in(event, {:binary, <<1, _::binary>> = bytes}, socket)
      when event in ["yjs", "yjs_sync"],
      do: awareness_in(bytes, socket)

  def handle_in(event, {:binary, bytes}, socket) when event in ["yjs", "yjs_sync"] do
    with {:ok, socket} <- check(socket),
         {:ok, message} <- Yex.Sync.message_decode(bytes) do
      frame(message, socket)
    else
      :revoked -> revoke(socket)
      {:error, _} -> reject(socket, "malformed")
    end
  end

  def handle_in(_event, _payload, socket), do: reject(socket, "unsupported")

  @impl true
  def handle_info({:collab_update, update}, socket) do
    case check(socket) do
      {:ok, socket} ->
        push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:sync, {:sync_update, update}})})
        {:noreply, socket}

      :revoked ->
        revoke(socket)
    end
  end

  # The section's JSON changed outside live editing. Every editor starts over from the new state.
  def handle_info(:collab_reset, socket), do: reset(socket)

  def handle_info(:join_presence, socket) do
    with_access(socket, fn socket ->
      Phoenix.PubSub.broadcast_from(
        Atlas.PubSub,
        self(),
        Collab.topic(socket.assigns.target),
        {:awareness_query, self()}
      )

      Process.send_after(self(), :heartbeat, @heartbeat_ms)
      {:noreply, announce(socket, socket.assigns.awareness.cursor)}
    end)
  end

  # A new state each time keeps the browsers from expiring this channel's state.
  def handle_info(:heartbeat, socket) do
    with_access(socket, fn socket ->
      Process.send_after(self(), :heartbeat, @heartbeat_ms)
      {:noreply, announce(socket, socket.assigns.awareness.cursor)}
    end)
  end

  def handle_info({:awareness_query, from}, socket) do
    with_access(socket, fn socket ->
      send(from, {:awareness, self(), state_message(socket)})
      {:noreply, socket}
    end)
  end

  def handle_info({:awareness, _from, {id, clock, state}}, socket) do
    with_access(socket, fn socket ->
      push(socket, "yjs", {:binary, Awareness.encode_frame(id, clock, state)})
      {:noreply, socket}
    end)
  end

  @impl true
  def terminate(_reason, %{assigns: %{awareness: awareness, target: target}}) do
    message = {:awareness, self(), {awareness.id, awareness.clock + 1, nil}}
    Phoenix.PubSub.broadcast_from(Atlas.PubSub, self(), Collab.topic(target), message)
  end

  def terminate(_reason, _socket), do: :ok

  defp awareness_in(bytes, socket) do
    %{window: window} = socket.assigns.awareness

    with true <- byte_size(bytes) <= Awareness.max_frame(),
         {:ok, window} <- Presence.take(window, System.monotonic_time(:millisecond)) do
      socket = put_awareness(socket, window: window)

      with_access(socket, fn socket ->
        case Awareness.client_cursor(bytes) do
          {:ok, cursor} -> {:noreply, announce(socket, cursor)}
          _ -> {:noreply, socket}
        end
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  # Sends the state of this channel to the others, under the channel's own client ID.
  defp announce(socket, cursor) do
    %{clock: clock} = socket.assigns.awareness
    socket = put_awareness(socket, cursor: cursor, clock: clock + 1)

    Phoenix.PubSub.broadcast_from(
      Atlas.PubSub,
      self(),
      Collab.topic(socket.assigns.target),
      {:awareness, self(), state_message(socket)}
    )

    socket
  end

  defp state_message(%{assigns: %{awareness: awareness, user: user}}),
    do: {awareness.id, awareness.clock, Presence.state(user, awareness.cursor)}

  defp put_awareness(socket, changes),
    do: assign(socket, :awareness, Map.merge(socket.assigns.awareness, Map.new(changes)))

  # Checks the session and the rights again, then runs `fun`. Access that ended closes the channel.
  defp with_access(socket, fun) do
    case check(socket) do
      {:ok, socket} -> fun.(socket)
      :revoked -> revoke(socket)
    end
  end

  defp frame({:sync, {:sync_step1, vector}}, socket) do
    case Collab.read_state(socket.assigns.target, socket.assigns.user) do
      {:ok, :reset} ->
        reset(socket)

      {:ok, state} ->
        {:noreply, answer(socket, state, vector)}

      {:error, :forbidden} ->
        revoke(socket)

      {:error, reason} ->
        reject(socket, reason)
    end
  end

  defp frame({:sync, {kind, update}}, socket) when kind in [:sync_step2, :sync_update] do
    %{target: target, user: user, can_write?: can_write?} = socket.assigns

    if can_write? do
      case Collab.apply_update(target, user, update) do
        {:ok, :reset} ->
          reset(socket)

        {:ok, :changed} ->
          Phoenix.PubSub.broadcast_from(
            Atlas.PubSub,
            self(),
            Collab.topic(target),
            {:collab_update, update}
          )

          {:reply, :ok, socket}

        {:ok, :unchanged} ->
          {:reply, :ok, socket}

        {:error, :forbidden} ->
          revoke(socket)

        {:error, reason} ->
          reject_update(socket, reason)
      end
    else
      reject_update(socket, :forbidden)
    end
  end

  # An auth or awareness query message is not part of the protocol here.
  defp frame(_message, socket), do: {:noreply, socket}

  # Sends what the client lacks. A writer also gets the server's vector, so it uploads what the
  # server lacks (edits made while it was offline).
  defp answer(socket, state, vector) do
    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state)
    {:ok, step2} = Yex.Sync.get_sync_step2(doc, vector)
    push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:sync, step2})})

    if socket.assigns.can_write? do
      {:ok, step1} = Yex.Sync.get_sync_step1(doc)
      push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:sync, step1})})
    end

    socket
  rescue
    _ ->
      push(socket, "rejected", %{reason: "malformed"})
      socket
  end

  defp check(%{assigns: %{session: session, target: target}} = socket) do
    with {:ok, user} <- AtlasWeb.RichTextSocket.user(session),
         {:ok, %{can_write?: can_write?}} <- Collab.authorize(target, user) do
      if socket.assigns[:can_write?] not in [nil, can_write?],
        do: push(socket, "permissions", %{canWrite: can_write?})

      {:ok, assign(socket, user: user, can_write?: can_write?)}
    else
      _ -> :revoked
    end
  end

  defp reset(socket) do
    push(socket, "reset", %{})
    {:stop, :normal, socket}
  end

  defp revoke(socket) do
    push(socket, "revoked", %{})
    {:stop, :normal, socket}
  end

  defp reject(socket, reason) do
    push(socket, "rejected", %{reason: reason_text(reason)})
    {:noreply, socket}
  end

  defp reject_update(socket, reason) do
    {:noreply, socket} = reject(socket, reason)
    {:reply, {:error, %{reason: reason_text(reason)}}, socket}
  end

  defp reason_text({:rejected, detail}) when is_binary(detail), do: detail
  defp reason_text({:rejected, detail}) when is_atom(detail), do: "rejected: #{detail}"
  defp reason_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_text(reason) when is_binary(reason), do: reason
  # Never echo an internal term to the client.
  defp reason_text(_), do: "rejected"
end
