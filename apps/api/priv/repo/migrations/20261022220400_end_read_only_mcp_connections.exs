defmodule Atlas.Repo.Migrations.EndReadOnlyMcpConnections do
  use Ecto.Migration

  # People allowed these connections as read-only. The tools can write now, so each person must
  # allow the app again on the new consent screen.
  def up, do: execute("DELETE FROM mcp_grants")

  def down, do: :ok
end
