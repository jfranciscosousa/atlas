defmodule Mix.Tasks.Atlas.CheckMigrations do
  @shortdoc "Runs every migration on an empty scratch database"
  @moduledoc """
  Creates an empty scratch database, runs all migrations on it, and drops it. A migration that works
  only on a database that is already migrated, for example one that reads a table a later
  migration creates, fails here. Test and development databases hide this kind of bug.

      mix atlas.check_migrations

  The scratch database is next to the configured one and has the suffix `_migcheck`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    if Mix.env() == :prod, do: Mix.raise("atlas.check_migrations does not run in production")
    Mix.Task.run("app.config")

    config = Application.fetch_env!(:atlas, Atlas.Repo)
    scratch = Keyword.fetch!(config, :database) <> "_migcheck"

    scratch_config =
      Keyword.merge(config,
        database: scratch,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        log: false
      )

    Application.put_env(:atlas, Atlas.Repo, scratch_config)

    drop(scratch_config)
    :ok = create(scratch_config)

    try do
      {:ok, versions, _} =
        Ecto.Migrator.with_repo(Atlas.Repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true, log: false)
        end)

      Mix.shell().info("Migrations apply to an empty database (#{length(versions)} migrations).")
    rescue
      error ->
        Mix.raise(
          "Migrations fail on an empty database (#{scratch}):\n" <> Exception.message(error)
        )
    after
      drop(scratch_config)

      # Later tasks in the same `mix` invocation, such as the test task in `mix precommit`, must use
      # the configured database, not the dropped scratch one.
      Application.put_env(:atlas, Atlas.Repo, config)
    end
  end

  defp create(config) do
    case Ecto.Adapters.Postgres.storage_up(config) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Cannot create #{config[:database]}: #{inspect(reason)}")
    end
  end

  defp drop(config), do: Ecto.Adapters.Postgres.storage_down(config)
end
