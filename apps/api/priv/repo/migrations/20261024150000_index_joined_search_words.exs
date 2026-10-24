defmodule Atlas.Repo.Migrations.IndexJoinedSearchWords do
  use Ecto.Migration

  # A text such as "M.A.77" now also indexes the joined word "ma77".
  def up do
    Atlas.Search.Projection.backfill!()
  end

  def down, do: :ok
end
