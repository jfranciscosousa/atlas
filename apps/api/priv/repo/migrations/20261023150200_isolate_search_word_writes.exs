defmodule Atlas.Repo.Migrations.IsolateSearchWordWrites do
  use Ecto.Migration

  def up do
    drop table(:search_words)

    create table(:search_words, primary_key: false) do
      add :kind, :text, primary_key: true
      add :record_id, :uuid, primary_key: true
      add :section, :text, primary_key: true
      add :word, :text, primary_key: true
      add :length, :integer, null: false
    end

    create index(:search_words, ["word gin_trgm_ops"], using: :gin, name: :search_words_trgm)
    create index(:search_words, [:length])
  end

  def down do
    raise "Search word isolation must not be reverted independently of the projection code"
  end
end
