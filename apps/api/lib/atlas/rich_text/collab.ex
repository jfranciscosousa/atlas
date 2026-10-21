defmodule Atlas.RichText.Collab do
  @moduledoc """
  Live editing of a rich-text section.

  Every section that declares `rich_text` can be edited together, with no code per resource.
  The editors share a Yjs document. This module holds the authoritative copy:

    * It checks every read and every update against the parent's own policies. Reading needs
      read access to the parent and its section field. Writing needs the section's `save_*`
      action: the same rule that guarded the old autosave.
    * It applies a client update to a fresh copy of the stored state, projects the result to
      BlockNote JSON, and saves that JSON through the section's `save_*` action. The update is
      stored only if that save succeeds, so the JSON column always equals the Yjs state.
    * One advisory lock per section serializes these steps.

  The stored state belongs to one section revision. If another writer changed the section's JSON
  (a plain save, an import, a restore), the state no longer matches. The state is then rebuilt
  from the JSON under a new epoch, and every channel on the section is told to close: a client
  that keeps its old document would merge two unrelated histories and duplicate the text.
  """

  require Ash.Query

  alias Atlas.Documents.Doc
  alias Atlas.RichText
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document

  @kinds %{
    "campaign" => Atlas.Campaigns.Campaign,
    "session" => Atlas.Campaigns.Session,
    "note" => Atlas.Content.Note,
    "player_log" => Atlas.Campaigns.PlayerLog,
    "character" => Atlas.Campaigns.Character
  }
  @max_update 512_000
  @max_state 4_000_000

  defstruct [:kind, :resource, :id, :section]

  @type t :: %__MODULE__{}
  @type error ::
          :forbidden
          | :update_too_large
          | :document_too_large
          | {:rejected, term()}

  @doc "Parses `kind:id:section`. The kind and section must be ones a resource declares."
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(ref) when is_binary(ref) do
    with [kind, id, section] <- String.split(ref, ":"),
         {:ok, resource} <- Map.fetch(@kinds, kind),
         {:ok, id} <- Ecto.UUID.cast(id),
         name when not is_nil(name) <-
           Enum.find(RichText.sections(resource), &(Atom.to_string(&1) == section)) do
      {:ok, %__MODULE__{kind: kind, resource: resource, id: id, section: name}}
    else
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc "The PubSub topic that carries the updates of one section."
  def topic(%__MODULE__{kind: kind, id: id, section: section}),
    do: "collab:#{kind}:#{id}:#{section}"

  @doc """
  Checks that the actor may read the section. Returns whether the actor may also write it.
  A section that does not exist and one the actor may not read give the same answer.
  """
  @spec authorize(t(), struct()) :: {:ok, %{can_write?: boolean()}} | {:error, :forbidden}
  def authorize(%__MODULE__{} = target, actor) do
    with {:ok, record} <- fetch(target, actor) do
      {:ok, %{can_write?: can_write?(target, record, actor)}}
    end
  end

  @doc """
  Checks access like `authorize/2`, and also returns the epoch of the document. A client keeps the
  first epoch it sees and starts over when a later one differs.
  """
  @spec open(t(), struct()) ::
          {:ok, %{can_write?: boolean(), epoch: pos_integer()}} | {:error, error()}
  def open(%__MODULE__{} = target, actor) do
    locked(target, fn ->
      with {:ok, record} <- fetch(target, actor),
           {:ok, row} <- row(target, record) do
        {:ok, %{can_write?: can_write?(target, record, actor), epoch: row.epoch}}
      end
    end)
  end

  @doc """
  The full Yjs state, created from the stored JSON the first time. Returns `:reset` when the state
  was just rebuilt: the caller's document is from an older epoch and must be dropped.
  """
  @spec read_state(t(), struct()) :: {:ok, binary() | :reset} | {:error, error()}
  def read_state(%__MODULE__{} = target, actor) do
    locked(target, fn ->
      with {:ok, record} <- fetch(target, actor),
           {:ok, row} <- row(target, record) do
        if row.reset?, do: {:ok, :reset}, else: {:ok, row.state}
      end
    end)
  end

  @doc """
  Applies a client update. Returns `:unchanged` when it adds nothing, or `:changed` once the new
  state and the JSON are stored.
  """
  @spec apply_update(t(), struct(), binary()) ::
          {:ok, :unchanged | :changed | :reset} | {:error, error()}
  def apply_update(%__MODULE__{}, _actor, update) when byte_size(update) > @max_update,
    do: {:error, :update_too_large}

  def apply_update(%__MODULE__{} = target, actor, update) when is_binary(update) do
    locked(target, fn ->
      with {:ok, record} <- fetch(target, actor),
           true <- can_write?(target, record, actor) || {:error, :forbidden},
           {:ok, row} <- row(target, record) do
        if row.reset?,
          do: {:ok, :reset},
          else: merge_and_store(target, record, actor, row, update)
      end
    end)
  end

  defp merge_and_store(target, record, actor, row, update) do
    with {:ok, state, blocks} <- merge(row.state, update) do
      if state == row.state,
        do: {:ok, :unchanged},
        else: store(target, record, actor, row, state, blocks)
    end
  end

  # Reads happen as the actor, so policies and field policies decide.
  defp fetch(%__MODULE__{resource: resource, id: id, section: section}, actor) do
    case Ash.get(resource, id, actor: actor, not_found_error?: false) do
      {:ok, %_{} = record} ->
        json = Map.fetch!(record, RichText.json_attribute(section))
        revision = Map.fetch!(record, RichText.revision_attribute(section))

        if forbidden_field?(json) or forbidden_field?(revision),
          do: {:error, :forbidden},
          else: {:ok, record}

      _ ->
        {:error, :forbidden}
    end
  end

  defp forbidden_field?(%Ash.ForbiddenField{}), do: true
  defp forbidden_field?(_), do: false

  defp can_write?(%__MODULE__{section: section}, record, actor) do
    Ash.can?({record, RichText.save_action(section)}, actor) == true
  end

  defp locked(target, fun) do
    result =
      Atlas.Repo.transaction(fn ->
        lock(target)

        case fun.() do
          {:error, reason} -> Atlas.Repo.rollback(reason)
          other -> other
        end
      end)

    case result do
      {:ok, {:ok, value}} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock(%__MODULE__{kind: kind, id: id, section: section}) do
    Ecto.Adapters.SQL.query!(
      Atlas.Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      ["#{kind}:#{id}:#{section}"]
    )
  end

  defp row(%__MODULE__{kind: kind, id: id, section: section} = target, record) do
    revision = Map.fetch!(record, RichText.revision_attribute(section))
    section = Atom.to_string(section)

    existing =
      Doc
      |> Ash.Query.filter(kind == ^kind and record_id == ^id and section == ^section)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        with {:ok, row} <- seed(target, record, revision, 1),
             do: {:ok, Map.put(row, :reset?, false)}

      %{revision: ^revision} = row ->
        {:ok, Map.put(row, :reset?, false)}

      stale ->
        with {:ok, row} <- seed(target, record, revision, stale.epoch + 1) do
          Phoenix.PubSub.broadcast(Atlas.PubSub, topic(target), :collab_reset)
          {:ok, Map.put(row, :reset?, true)}
        end
    end
  end

  defp seed(%__MODULE__{section: section} = target, record, revision, epoch) do
    doc = record |> Map.fetch!(RichText.json_attribute(section)) |> Blocks.seed()

    with {:ok, _} <- Blocks.project(doc),
         {:ok, state} <- Yex.encode_state_as_update(doc) do
      {:ok, put(target, state, revision, epoch)}
    else
      _ -> {:error, {:rejected, :unseedable}}
    end
  end

  defp put(%__MODULE__{kind: kind, id: id, section: section}, state, revision, epoch) do
    Ash.create!(
      Doc,
      %{
        kind: kind,
        record_id: id,
        section: Atom.to_string(section),
        state: state,
        revision: revision,
        epoch: epoch
      },
      action: :put,
      authorize?: false
    )
  end

  # The update goes onto a fresh copy of the stored state: a failed update never leaves a
  # half-applied live document behind.
  defp merge(state, update) do
    doc = Yex.Doc.new()

    with :ok <- Yex.apply_update(doc, state),
         :ok <- Yex.apply_update(doc, update),
         {:ok, blocks} <- Blocks.project(doc),
         {:ok, merged} <- Yex.encode_state_as_update(doc),
         :ok <- if(byte_size(merged) <= @max_state, do: :ok, else: {:error, :document_too_large}) do
      {:ok, merged, blocks}
    else
      {:error, :document_too_large} = error -> error
      {:error, reason} -> {:error, {:rejected, reason}}
      _ -> {:error, {:rejected, :update}}
    end
  rescue
    _ -> {:error, {:rejected, :update}}
  end

  defp store(%__MODULE__{section: section} = target, record, actor, row, state, blocks) do
    revision = Map.fetch!(record, RichText.revision_attribute(section))

    result =
      record
      |> Ash.Changeset.for_update(
        RichText.save_action(section),
        %{json: blocks, schema_version: Document.schema_version(), expected_revision: revision},
        actor: actor
      )
      |> Ash.update()

    case result do
      {:ok, saved} ->
        put(target, state, Map.fetch!(saved, RichText.revision_attribute(section)), row.epoch)
        {:ok, :changed}

      {:error, %Ash.Error.Forbidden{}} ->
        {:error, :forbidden}

      {:error, error} ->
        {:error, {:rejected, error_text(error)}}
    end
  end

  # Ash error messages carry the document and a stack trace. Only the validation texts go out.
  defp error_text(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.map(&Map.get(&1, :message))
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> "the document is not valid"
      messages -> Enum.join(messages, "; ")
    end
  end

  defp error_text(_), do: "the document is not valid"
end
