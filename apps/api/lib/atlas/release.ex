defmodule Atlas.Release do
  @moduledoc """
  Release tasks. The container runs `bin/atlas eval "Atlas.Release.migrate()"` before it starts.
  """

  @app :atlas

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
