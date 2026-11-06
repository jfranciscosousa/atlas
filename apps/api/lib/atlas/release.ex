defmodule Atlas.Release do
  @moduledoc """
  Release tasks. Startup runs `bin/atlas eval 'Atlas.Release.check_schema!()'`.
  Migrations are available only as the explicit operator command
  `bin/atlas eval 'Atlas.Release.migrate()'`.
  """

  @app :atlas

  def check_schema! do
    Application.load(@app)

    repos = Application.fetch_env!(@app, :ecto_repos)

    unless repos != [] and Enum.all?(repos, &schema_ready?/1) do
      raise "Schema readiness check failed; apply required migrations explicitly before starting"
    end

    :ok
  end

  defp schema_ready?(repo) do
    # with_repo starts only repo dependencies, not Atlas.Application or its workers.
    match?({:ok, true, _}, Ecto.Migrator.with_repo(repo, &Atlas.SchemaReadiness.ready?/1))
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
