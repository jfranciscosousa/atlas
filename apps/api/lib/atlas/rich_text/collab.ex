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
  alias Atlas.Kinds
  alias Atlas.RichText
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document

  @max_update 512_000
  @max_state 4_000_000

  # A single call has not read the record and the stored document yet: it reads them itself.
  @unloaded %{record: :unloaded, doc: :unloaded}

  defstruct [:kind, :resource, :id, :section]

  @type t :: %__MODULE__{}
  @type error ::
          :forbidden
          | :stale
          | :update_too_large
          | :document_too_large
          | {:rejected, term()}

  @doc "Parses `kind:id:section`. The kind and section must be ones a resource declares."
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(ref) when is_binary(ref) do
    with [kind, id, section] <- String.split(ref, ":"),
         {:ok, kind_atom} <- Kinds.fetch(kind),
         {:ok, id} <- Ecto.UUID.cast(id),
         name when not is_nil(name) <-
           Enum.find(Kinds.sections(kind_atom), &(Atom.to_string(&1) == section)) do
      {:ok, %__MODULE__{kind: kind, resource: Kinds.resource(kind_atom), id: id, section: name}}
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
    locked(target, fn -> state_of(target, actor, @unloaded) end)
  end

  @doc """
  Reads the state of many sections, like `read_state/2` for each, in the order of `targets`. The
  records and the stored documents are read in one query each, so the number of queries does not
  grow with the number of sections. Each result stands alone: one error does not stop the others.
  """
  @spec read_states([t()], struct()) :: [{:ok, binary() | :reset} | {:error, error()}]
  def read_states(targets, actor) do
    result =
      Atlas.Repo.transaction(fn ->
        lock_all(targets)
        loaded = preload(targets, actor)
        Enum.map(targets, &state_of(&1, actor, Map.fetch!(loaded, topic(&1))))
      end)

    case result do
      {:ok, states} -> states
      {:error, reason} -> Enum.map(targets, fn _ -> {:error, reason} end)
    end
  end

  defp state_of(target, actor, loaded) do
    with {:ok, record} <- record_for(target, actor, loaded.record),
         {:ok, row} <- row(target, record, loaded.doc) do
      if row.reset?, do: {:ok, :reset}, else: {:ok, row.state}
    end
  end

  @doc """
  Applies a client update. Returns `:unchanged` when it adds nothing, or `{:changed, revision}` once the new
  state and the JSON are stored. `revision` is the saved section revision.

  With `expected_revision`, the update is refused with `:stale` unless the section still has that
  revision: the writer must have read the latest text.
  """
  @spec apply_update(t(), struct(), binary(), keyword()) ::
          {:ok, :unchanged | {:changed, integer()} | :reset} | {:error, error()}
  def apply_update(target, actor, update, opts \\ [])

  def apply_update(%__MODULE__{} = target, actor, update, opts) when is_binary(update) do
    locked(target, fn -> store_update(target, actor, update, opts, @unloaded) end)
  end

  defp store_update(%__MODULE__{}, _actor, update, _opts, _loaded)
       when byte_size(update) > @max_update,
       do: {:error, :update_too_large}

  defp store_update(target, actor, update, opts, loaded) do
    with {:ok, record} <- record_for(target, actor, loaded.record),
         true <- can_write?(target, record, actor) || {:error, :forbidden},
         :ok <- current?(target, record, opts[:expected_revision]),
         {:ok, row} <- row(target, record, loaded.doc) do
      if row.reset?,
        do: {:ok, :reset},
        else: merge_and_store(target, record, actor, row, update)
    end
  end

  @doc """
  Applies updates to several sections as one transaction: all are stored, or none. Each entry is
  `{target, update, opts}` with the options of `apply_update/4`. On failure, nothing is stored and
  the result names the index of the entry that failed.

  The locks of all sections are taken first, in a fixed order, so two batches that share sections
  cannot wait for each other. A section that was rebuilt since the caller read it counts as `:stale`.
  The records and the stored documents are read in one query each, so the number of queries to
  read does not grow with the number of sections.
  """
  @spec apply_updates([{t(), binary(), keyword()}], struct()) ::
          {:ok, [:unchanged | {:changed, integer()}]} | {:error, non_neg_integer(), error()}
  def apply_updates(entries, actor) do
    ordered =
      entries
      |> Enum.with_index()
      |> Enum.sort_by(fn {{target, _update, _opts}, _index} -> topic(target) end)

    result =
      Atlas.Repo.transaction(fn ->
        targets = Enum.map(entries, &elem(&1, 0))
        lock_all(targets)
        loaded = preload(targets, actor)

        Enum.map(ordered, fn {{target, update, opts}, index} ->
          case store_update(target, actor, update, opts, Map.fetch!(loaded, topic(target))) do
            {:ok, :reset} -> Atlas.Repo.rollback({index, :stale})
            {:ok, outcome} -> {index, outcome}
            {:error, reason} -> Atlas.Repo.rollback({index, reason})
          end
        end)
      end)

    case result do
      {:ok, outcomes} -> {:ok, outcomes |> Enum.sort() |> Enum.map(&elem(&1, 1))}
      {:error, {index, reason}} -> {:error, index, reason}
    end
  end

  # Reads, for all targets at once, the record and the stored document of each. A record that the
  # actor may not read is `nil`.
  defp preload(targets, actor) do
    records =
      targets
      |> Enum.group_by(& &1.resource, & &1.id)
      |> Enum.flat_map(fn {resource, ids} ->
        resource
        |> Atlas.Mcp.Records.fetch(ids, actor)
        |> Enum.map(fn {id, record} -> {{resource, id}, record} end)
      end)
      |> Map.new()

    kinds = targets |> Enum.map(& &1.kind) |> Enum.uniq()
    ids = targets |> Enum.map(& &1.id) |> Enum.uniq()

    docs =
      Doc
      |> Ash.Query.filter(kind in ^kinds and record_id in ^ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{{&1.kind, &1.record_id, &1.section}, &1})

    Map.new(targets, fn %__MODULE__{} = target ->
      {topic(target),
       %{
         record: Map.get(records, {target.resource, target.id}),
         doc: Map.get(docs, {target.kind, target.id, Atom.to_string(target.section)})
       }}
    end)
  end

  defp current?(_target, _record, nil), do: :ok

  defp current?(%__MODULE__{section: section}, record, expected) do
    if Map.fetch!(record, RichText.revision_attribute(section)) == expected,
      do: :ok,
      else: {:error, :stale}
  end

  defp merge_and_store(target, record, actor, row, update) do
    with {:ok, state, blocks} <- merge(row.state, update) do
      if state == row.state,
        do: {:ok, :unchanged},
        else: store(target, record, actor, row, state, blocks)
    end
  end

  # Reads happen as the actor, so policies and field policies decide.
  defp fetch(target, actor), do: record_for(target, actor, :unloaded)

  # `loaded` is a record that a batch read, `nil` for one that the actor may not read, or `:unloaded`.
  defp record_for(%__MODULE__{resource: resource, id: id} = target, actor, :unloaded) do
    case Ash.get(resource, id, actor: actor, not_found_error?: false) do
      {:ok, %_{} = record} -> admit(target, record)
      _ -> {:error, :forbidden}
    end
  end

  defp record_for(_target, _actor, nil), do: {:error, :forbidden}
  defp record_for(target, _actor, %_{} = record), do: admit(target, record)

  defp admit(%__MODULE__{section: section} = target, record) do
    json = Map.fetch!(record, RichText.json_attribute(section))
    revision = Map.fetch!(record, RichText.revision_attribute(section))

    if forbidden_field?(json) or forbidden_field?(revision) or not kind_matches?(target, record),
      do: {:error, :forbidden},
      else: {:ok, record}
  end

  @doc """
  True when the record is of the kind that the target names. A resource that stores several kinds
  must not open a record under another kind: it would get a second document.
  """
  @spec kind_matches?(t(), struct()) :: boolean()
  def kind_matches?(%__MODULE__{kind: kind, resource: resource}, record),
    do: Atom.to_string(Kinds.record_kind(resource, record)) == kind

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
      # A rejection inside the save's own transaction rolls back this one with the changeset.
      {:error, %Ash.Changeset{} = changeset} -> {:error, {:rejected, error_text(changeset)}}
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

  # Locks many sections in one query, in a fixed order. The order is the same for every batch, so
  # two batches that share sections cannot wait for each other.
  defp lock_all(targets) do
    keys = targets |> Enum.map(&"#{&1.kind}:#{&1.id}:#{&1.section}") |> Enum.uniq()

    Ecto.Adapters.SQL.query!(
      Atlas.Repo,
      """
      SELECT pg_advisory_xact_lock(hashtextextended(key, 0))
      FROM (SELECT key FROM unnest($1::text[]) AS key ORDER BY key) AS ordered
      """,
      [keys]
    )
  end

  defp row(target, record, doc \\ :unloaded)

  defp row(%__MODULE__{kind: kind, id: id, section: section} = target, record, doc) do
    revision = Map.fetch!(record, RichText.revision_attribute(section))
    section = Atom.to_string(section)

    existing =
      if doc == :unloaded do
        Doc
        |> Ash.Query.filter(kind == ^kind and record_id == ^id and section == ^section)
        |> Ash.read_one!(authorize?: false)
      else
        doc
      end

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
        saved_revision = Map.fetch!(saved, RichText.revision_attribute(section))
        put(target, state, saved_revision, row.epoch)
        {:ok, {:changed, saved_revision}}

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
