defmodule Atlas.Repo.Migrations.DropImageParents do
  @moduledoc """
  Images are standalone: access no longer follows a parent section. The columns that named the
  parent are dropped. Rolling back adds them with placeholder values, because the old parents
  are not kept.
  """

  use Ecto.Migration

  def up do
    drop_if_exists index(:images, [:parent_type, :parent_id, :section])

    alter table(:images) do
      remove :parent_type
      remove :parent_id
      remove :section
    end
  end

  def down do
    alter table(:images) do
      add :parent_type, :text, null: false, default: "campaign"
      add :parent_id, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :section, :text, null: false, default: "description"
    end

    create index(:images, [:parent_type, :parent_id, :section])
  end
end
