defmodule Atlas.Images.Cleanup do
  @moduledoc "Deletes unreferenced images daily. New uploads have a 24-hour grace period."
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Repo
  alias Atlas.RichText

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    references = references_sql()

    %{rows: rows} =
      Repo.query!("""
      SELECT id FROM images
      WHERE inserted_at < now() - interval '24 hours'
        AND NOT EXISTS (#{references})
      """)

    Enum.reduce_while(rows, :ok, fn [id], :ok ->
      case delete_unused(id, references) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_unused(id, references) do
    Repo.transaction(fn ->
      # Saves hold a shared lock on referenced images until their JSON commits.
      case Repo.query!("SELECT storage_key FROM images WHERE id = $1 FOR UPDATE", [id]).rows do
        [] ->
          :ok

        [[key]] ->
          unused? =
            Repo.query!(
              "SELECT id FROM images WHERE id = $1 AND NOT EXISTS (#{references})",
              [id]
            ).num_rows == 1

          if unused? do
            # Keep metadata on storage failure so Oban can retry. Delete is idempotent.
            case Atlas.Storage.delete(key) do
              :ok -> Repo.query!("DELETE FROM images WHERE id = $1", [id])
              {:error, reason} -> Repo.rollback(reason)
            end
          end
      end
    end)
  end

  defp references_sql do
    Application.fetch_env!(:atlas, :ash_domains)
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.flat_map(fn resource ->
      Enum.map(RichText.sections(resource), fn section ->
        table = quote_identifier(AshPostgres.DataLayer.Info.table(resource))
        column = quote_identifier(RichText.json_attribute(section))

        """
        SELECT 1 FROM #{table}
        WHERE jsonb_path_exists(#{column},
          '$.** ? (@.type == "image" && @.props.url == $ref)',
          jsonb_build_object('ref', 'atlas-image:' || images.id::text))
        """
      end)
    end)
    |> Enum.join(" UNION ALL ")
  end

  defp quote_identifier(value), do: "\"" <> String.replace(to_string(value), "\"", "\"\"") <> "\""
end
