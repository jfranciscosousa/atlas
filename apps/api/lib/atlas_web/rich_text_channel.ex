defmodule AtlasWeb.RichTextChannel do
  @moduledoc """
  One editor's connection to one rich-text section: `doc:<kind>:<id>:<section>`.

  The channel speaks the Yjs sync protocol. It trusts nothing it learned earlier: before it
  handles each client frame and before it delivers each update, it checks the signed-in session
  and the user's rights on the section again (`Atlas.RichText.Collab.authorize/2`). A user who
  lost access gets one `revoked` message and the channel closes. A user who lost only the right
  to write gets a `permissions` message and the channel turns read-only.

  Awareness frames (cursors, names) are dropped: a client could claim any name.
  """
  use Phoenix.Channel

  alias Atlas.RichText.Collab

  @impl true
  def join("doc:" <> ref, _params, socket) do
    with {:ok, target} <- Collab.parse(ref),
         {:ok, socket} <- check(assign(socket, :target, target)),
         {:ok, %{epoch: epoch}} <- Collab.open(target, socket.assigns.user) do
      Phoenix.PubSub.subscribe(Atlas.PubSub, Collab.topic(target))
      {:ok, %{canWrite: socket.assigns.can_write?, epoch: epoch}, socket}
    else
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
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

          {:noreply, socket}

        {:ok, :unchanged} ->
          {:noreply, socket}

        {:error, :forbidden} ->
          revoke(socket)

        {:error, reason} ->
          reject(socket, reason)
      end
    else
      reject(socket, :forbidden)
    end
  end

  # Awareness and anything else is not part of the protocol here.
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

  defp reason_text({:rejected, detail}) when is_binary(detail), do: detail
  defp reason_text({:rejected, detail}) when is_atom(detail), do: "rejected: #{detail}"
  defp reason_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_text(reason) when is_binary(reason), do: reason
  # Never echo an internal term to the client.
  defp reason_text(_), do: "rejected"
end
