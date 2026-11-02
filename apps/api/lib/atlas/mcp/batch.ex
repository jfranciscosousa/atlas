defmodule Atlas.Mcp.Batch do
  @moduledoc """
  The limits of the MCP tools that work on many records in one call.
  """

  @max_items 50
  @max_operations 500

  @doc "The most records, sections or edits that one call takes."
  def max_items, do: @max_items

  @doc "The most operations that one `edit_blocks_many` call takes in total."
  def max_operations, do: @max_operations
end
