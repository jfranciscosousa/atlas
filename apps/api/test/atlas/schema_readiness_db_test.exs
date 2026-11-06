defmodule Atlas.SchemaReadinessDBTest do
  use Atlas.DataCase, async: true

  alias Atlas.SchemaReadiness

  test "packaged schema can be checked in a read-only sandbox transaction" do
    Repo.query!("SET TRANSACTION READ ONLY", [], log: false, sandbox_subtransaction: false)
    assert Repo.query!("SHOW transaction_read_only", [], log: false).rows == [["on"]]
    before = Repo.query!("SELECT version FROM schema_migrations ORDER BY version", [], log: false)

    assert SchemaReadiness.ready?()

    after_check =
      Repo.query!("SELECT version FROM schema_migrations ORDER BY version", [], log: false)

    assert after_check.rows == before.rows
  end

  test "an unapplied packaged migration is rejected without changing the database" do
    path =
      Path.join(System.tmp_dir!(), "atlas-missing-schema-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    File.write!(Path.join(path, "9223372036854775807_missing.exs"), "raise \"never execute\"")

    Repo.query!("SET TRANSACTION READ ONLY", [], log: false, sandbox_subtransaction: false)
    refute SchemaReadiness.ready?(Repo, path)
  end
end
