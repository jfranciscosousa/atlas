defmodule Atlas.SchemaReadiness do
  @moduledoc """
  Read-only comparison of packaged migration IDs with the database.

  Extra applied IDs are allowed so an older image can be used after reviewed
  additive migrations. This checks completeness, not migration compatibility.
  No migration code is loaded or executed, and no migration table is created.
  """

  def ready?(repo \\ Atlas.Repo, migrations_path \\ packaged_path()) do
    with {:ok, required} <- packaged_versions(migrations_path),
         {:ok, %{rows: rows}} <-
           repo.query("SELECT version FROM schema_migrations", [], timeout: 2_000, log: false) do
      applied = MapSet.new(rows, fn [version] when is_integer(version) -> version end)
      MapSet.subset?(required, applied)
    else
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @doc false
  def packaged_path, do: Application.app_dir(:atlas, "priv/repo/migrations")

  @doc false
  def packaged_versions(path \\ packaged_path()) do
    with {:ok, files} <- File.ls(path) do
      versions =
        Enum.flat_map(files, fn file ->
          case Regex.run(~r/\A([0-9]+)_.+\.exs\z/, file) do
            [_, version] -> [String.to_integer(version)]
            _ -> []
          end
        end)

      if versions != [] and length(versions) == MapSet.size(MapSet.new(versions)) do
        {:ok, MapSet.new(versions)}
      else
        {:error, :invalid_migration_package}
      end
    end
  end
end
