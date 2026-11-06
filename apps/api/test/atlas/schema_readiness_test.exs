defmodule Atlas.SchemaReadinessTest do
  use ExUnit.Case, async: true

  alias Atlas.SchemaReadiness

  defmodule ReadOnlyRepo do
    def query(sql, params, opts) do
      send(self(), {:query, sql, params, opts})

      case Process.get(:schema_query_result) do
        :raise -> raise "secret database credentials"
        :exit -> exit({:connection_error, "secret database credentials"})
        result -> result
      end
    end
  end

  setup do
    path = Path.join(System.tmp_dir!(), "atlas-schema-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    File.write!(Path.join(path, "1_first.exs"), "raise \"must never execute migrations\"")
    File.write!(Path.join(path, "2_second.exs"), "raise \"must never execute migrations\"")
    %{path: path}
  end

  test "only SELECT is issued, all required IDs must be present, and extra IDs are allowed", %{
    path: path
  } do
    Process.put(:schema_query_result, {:ok, %{rows: [[1], [2], [999]]}})
    assert SchemaReadiness.ready?(ReadOnlyRepo, path)

    assert_received {:query, "SELECT version FROM schema_migrations", [], opts}
    assert opts[:log] == false
    assert opts[:timeout] == 2_000
    refute_received {:query, _, _, _}

    # A newer maximum does not imply completeness: gaps must fail.
    Process.put(:schema_query_result, {:ok, %{rows: [[1], [999]]}})
    refute SchemaReadiness.ready?(ReadOnlyRepo, path)
  end

  test "empty, absent and duplicate migration packages fail closed", %{path: path} do
    Process.put(:schema_query_result, {:ok, %{rows: [[1], [2]]}})
    File.write!(Path.join(path, "2_duplicate.exs"), "")
    refute SchemaReadiness.ready?(ReadOnlyRepo, path)
    refute SchemaReadiness.ready?(ReadOnlyRepo, Path.join(path, "absent"))

    empty = Path.join(path, "empty")
    File.mkdir!(empty)
    refute SchemaReadiness.ready?(ReadOnlyRepo, empty)
    refute_received {:query, _, _, _}
  end

  test "uninitialized schema, DB failures, exceptions and exits fail without logging details", %{
    path: path
  } do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for result <- [
              {:error, :undefined_table},
              {:error, "secret database credentials"},
              :raise,
              :exit,
              {:ok, %{rows: [["invalid"]]}}
            ] do
          Process.put(:schema_query_result, result)
          refute SchemaReadiness.ready?(ReadOnlyRepo, path)
        end
      end)

    refute log =~ "secret"
  end
end
