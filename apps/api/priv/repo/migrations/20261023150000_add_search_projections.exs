defmodule Atlas.Repo.Migrations.AddSearchProjections do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    create table(:search_words, primary_key: false) do
      add :word, :text, primary_key: true
      add :length, :integer, null: false
    end

    create index(:search_words, ["word gin_trgm_ops"], using: :gin, name: :search_words_trgm)
    create index(:search_words, [:length])

    create table(:search_sections, primary_key: false) do
      add :kind, :text, primary_key: true
      add :record_id, :uuid, primary_key: true
      add :section, :text, primary_key: true
      add :revision, :bigint, null: false
      add :blocks, {:array, :map}, null: false
      add :words, {:array, :text}, null: false
      add :has_mentions, :boolean, null: false
    end

    create index(:search_sections, [:words], using: :gin)
    create index(:search_sections, [:kind, :record_id], where: "has_mentions")
  end

  def down do
    drop table(:search_sections)
    drop table(:search_words)
  end
end
