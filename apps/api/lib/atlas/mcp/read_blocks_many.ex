defmodule Atlas.Mcp.ReadBlocksMany do
  @moduledoc """
  Reads blocks of many sections in one call. It implements `read_blocks_many`: a list of reads,
  each one the input of `read_blocks` (see `Atlas.Mcp.ReadBlocks`).

  Each read stands alone, with the read rules of its section. A read that fails gives an `error`
  in its own result and does not stop the others. The number of queries does not grow with the
  number of reads (see `Atlas.Mcp.ReadBlocks.read_many/2`).
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Mcp.ReadBlocks

  @impl true
  def run(input, _opts, %{actor: actor}) do
    reads = input.arguments.reads

    results =
      reads
      |> Enum.zip(ReadBlocks.read_many(actor, reads))
      |> Enum.map(fn {read, outcome} ->
        identity = Map.take(read, [:kind, :id, :section])

        case outcome do
          {:ok, result} -> Map.merge(identity, result)
          {:error, message} -> Map.put(identity, :error, message)
        end
      end)

    {:ok, %{results: results}}
  end
end
