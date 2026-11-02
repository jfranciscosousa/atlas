defmodule Atlas.Mcp.EditBlocksMany do
  @moduledoc """
  Edits the blocks of many sections in one call. It implements `edit_blocks_many`: a list of
  edits, each one the input of `edit_blocks` (see `Atlas.Mcp.EditBlocks`).

  All edits are stored in one transaction: if one fails, nothing changes. Every guard of
  `edit_blocks` applies to each edit. The editors that have a section open receive its update only
  after the transaction commits.

  The records and the stored documents are read in one query each, for planning and again for
  storing, so the number of queries to read does not grow with the number of edits.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Mcp.{Batch, EditBlocks}
  alias Atlas.RichText.Collab

  @impl true
  def run(input, _opts, %{actor: actor}) do
    edits = Enum.map(input.arguments.edits, &normalize/1)

    with :ok <- within_limit(edits),
         {:ok, targets} <- targets(edits),
         :ok <- distinct(targets),
         {:ok, plans} <- plan_all(edits, targets, actor),
         {:ok, outcomes} <- store(plans, actor) do
      results =
        plans
        |> Enum.zip(outcomes)
        |> Enum.map(fn {plan, outcome} ->
          plan.target
          |> identity()
          |> Map.merge(EditBlocks.publish(plan, outcome))
        end)

      {:ok, %{saved: Enum.any?(results, & &1.saved), results: results}}
    else
      {:error, message} -> {:error, error(message)}
    end
  end

  defp normalize(edit) do
    %{
      kind: edit.kind,
      id: edit.id,
      section: edit.section,
      operations: edit.operations,
      expected_revision: edit[:expected_revision],
      remove_images: edit[:remove_images] || false,
      delete_many: edit[:delete_many] || false
    }
  end

  defp within_limit(edits) do
    operations = edits |> Enum.map(&length(&1.operations)) |> Enum.sum()

    if operations > Batch.max_operations(),
      do:
        {:error,
         "has #{operations} operations in total, more than #{Batch.max_operations()}: send fewer at a time"},
      else: :ok
  end

  defp targets(edits) do
    edits
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {edit, index}, {:ok, targets} ->
      case EditBlocks.target_of(edit) do
        {:ok, target} -> {:cont, {:ok, [target | targets]}}
        {:error, reason} -> {:halt, {:error, failure(index, reason)}}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.reverse(targets)}
      error -> error
    end
  end

  # Two edits of one section would each start from the same text: the operations belong in one edit.
  defp distinct(targets) do
    topics = Enum.map(targets, &Collab.topic/1)

    case topics -- Enum.uniq(topics) do
      [] -> :ok
      [topic | _] -> {:error, "edits the section #{topic} twice: put its operations in one edit"}
    end
  end

  defp plan_all(edits, targets, actor) do
    states = Collab.read_states(targets, actor)

    [edits, targets, states]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{edit, target, state}, index}, {:ok, plans} ->
      case plan(actor, edit, target, state) do
        {:ok, plan} -> {:cont, {:ok, [plan | plans]}}
        {:error, reason} -> {:halt, {:error, failure(index, reason)}}
      end
    end)
    |> case do
      {:ok, plans} -> {:ok, Enum.reverse(plans)}
      error -> error
    end
  end

  # A section that was rebuilt since the batch read it is read again, on its own.
  defp plan(actor, edit, target, {:ok, :reset}) do
    with {:ok, state} <- EditBlocks.state(target, actor), do: EditBlocks.plan(actor, edit, state)
  end

  defp plan(actor, edit, _target, {:ok, state}), do: EditBlocks.plan(actor, edit, state)
  defp plan(_actor, _edit, _target, {:error, reason}), do: {:error, reason}

  defp store(plans, actor) do
    entries = Enum.map(plans, &{&1.target, &1.update, expected_revision: &1.expected_revision})

    case Collab.apply_updates(entries, actor) do
      {:ok, outcomes} -> {:ok, outcomes}
      {:error, index, reason} -> {:error, failure(index, reason)}
    end
  end

  defp failure(index, reason),
    do: "edits[#{index}]: #{EditBlocks.error_text(reason)}. Nothing was changed"

  defp identity(target), do: %{kind: target.kind, id: target.id, section: target.section}

  defp error(message),
    do: Ash.Error.Changes.InvalidArgument.exception(field: :edits, message: message)
end
