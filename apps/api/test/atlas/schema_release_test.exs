defmodule Atlas.SchemaReleaseTest do
  use ExUnit.Case, async: false

  defmodule RepoAdapter do
    def ensure_all_started(_config, _mode), do: {:ok, []}
  end

  defmodule ReadOnlyRepo do
    def config, do: []
    def __adapter__, do: Atlas.SchemaReleaseTest.RepoAdapter

    def start_link(opts) do
      send(self(), {:repo_started, opts})
      {:ok, self()}
    end

    def stop, do: send(self(), :repo_stopped)

    def query(sql, params, opts) do
      send(self(), {:release_query, sql, params, opts})

      case Process.get(:release_schema_result) do
        :raise -> raise "secret connection string"
        result -> result
      end
    end
  end

  setup do
    previous = Application.fetch_env!(:atlas, :ecto_repos)
    Application.put_env(:atlas, :ecto_repos, [ReadOnlyRepo])
    on_exit(fn -> Application.put_env(:atlas, :ecto_repos, previous) end)
    :ok
  end

  test "startup guard uses with_repo lifecycle and only reads migration IDs" do
    {:ok, versions} = Atlas.SchemaReadiness.packaged_versions()
    Process.put(:release_schema_result, {:ok, %{rows: Enum.map(versions, &[&1])}})

    assert Atlas.Release.check_schema!() == :ok
    assert_received {:repo_started, [pool_size: 2]}
    assert_received :repo_stopped
    assert_received {:release_query, "SELECT version FROM schema_migrations", [], opts}
    assert opts[:log] == false
    assert opts[:timeout] == 2_000
    refute_received {:release_query, _, _, _}
  end

  test "incomplete, absent or inaccessible schema prevents startup with a generic error" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for result <- [{:ok, %{rows: []}}, {:error, :undefined_table}, :raise] do
          Process.put(:release_schema_result, result)

          assert_raise RuntimeError,
                       "Schema readiness check failed; apply required migrations explicitly before starting",
                       fn -> Atlas.Release.check_schema!() end

          assert_received :repo_stopped
        end
      end)

    refute log =~ "secret"
  end
end
