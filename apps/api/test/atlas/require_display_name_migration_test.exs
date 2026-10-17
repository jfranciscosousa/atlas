Code.require_file("../../priv/repo/migrations/20261017144436_require_display_name.exs", __DIR__)

defmodule Atlas.RequireDisplayNameMigrationTest do
  use Atlas.DataCase, async: true

  alias Atlas.Repo.Migrations.RequireDisplayName
  alias Ecto.Migration.Runner

  test "the migration humanizes missing names, preserves names, and requires a name" do
    # A temporary table keeps the migration test separate from application data.
    Repo.query!("CREATE TEMP TABLE users (email citext, display_name text) ON COMMIT DROP")

    examples = [
      {"jane.doe@example.com", nil, "Jane Doe"},
      {"john_doe-smith+news@example.com", nil, "John Doe Smith"},
      {"jane@example.com", "  ", "Jane"},
      {"+tag@example.com", nil, "User"},
      {String.duplicate("a", 120) <> "@example.com", nil, "A" <> String.duplicate("a", 99)},
      {"keep@example.com", "My chosen name", "My chosen name"}
    ]

    for {email, name, _expected} <- examples do
      Repo.query!("INSERT INTO users (email, display_name) VALUES ($1, $2)", [email, name])
    end

    runner =
      start_supervised!(
        {Runner,
         {self(), Repo, Repo.config(), RequireDisplayName, :forward, :up,
          %{level: false, sql: false}}}
      )

    Runner.metadata(runner, [])
    RequireDisplayName.up()
    Runner.flush()

    for {email, _name, expected} <- examples do
      assert %{rows: [[^expected]]} =
               Repo.query!("SELECT display_name FROM users WHERE email = $1", [email])
    end

    assert %{rows: [[true]]} =
             Repo.query!("""
             SELECT attnotnull FROM pg_attribute
             WHERE attrelid = 'pg_temp.users'::regclass AND attname = 'display_name'
             """)

    RequireDisplayName.down()
    Runner.flush()
    Repo.query!("INSERT INTO users (email, display_name) VALUES ('rollback@example.com', NULL)")
  end
end
