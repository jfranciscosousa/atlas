defmodule AtlasWeb.HealthController do
  use AtlasWeb, :controller

  @max_index_bytes 256 * 1024
  @max_asset_bytes 64 * 1024 * 1024
  @max_references 256

  def show(conn, _params) do
    status =
      if ready?(Application.get_env(:atlas, :serve_frontend, false)),
        do: :no_content,
        else: :service_unavailable

    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, "")
  end

  @doc false
  def ready?(
        frontend?,
        repo \\ Atlas.Repo,
        static_root \\ Application.app_dir(:atlas, "priv/static")
      ) do
    if frontend? do
      Atlas.SchemaReadiness.ready?(repo) and frontend_ready?(static_root)
    else
      match?({:ok, _}, repo.query("SELECT 1", [], timeout: 2_000, log: false))
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @doc false
  def frontend_ready?(root) do
    with true <- regular_path?(root, ["index.html"], @max_index_bytes),
         {:ok, html} <- read_index(Path.join(root, "index.html")),
         true <- is_binary(html) and byte_size(html) <= @max_index_bytes do
      # TanStack's entrypoint can be an inline module import rather than script src.
      # Inspect only the bounded index; never read the (potentially large) bundles.
      html = Regex.replace(~r/<!--.*?-->/s, html, "")

      references =
        Regex.scan(~r/["']([^"'<>\s]+\.(?:m?js|css)(?:[?#][^"'<>\s]*)?)["']/i, html,
          capture: :all_but_first
        )
        |> List.flatten()
        |> Enum.reject(&external_reference?/1)
        |> Enum.uniq()

      Regex.match?(~r/<!doctype\s+html\b/i, html) and
        Regex.match?(~r/<html\b/i, html) and Regex.match?(~r/<head\b/i, html) and
        Regex.match?(~r/<body\b/i, html) and Regex.match?(~r/<script\b/i, html) and
        Regex.match?(~r/<\/html\s*>/i, html) and
        length(references) <= @max_references and
        Enum.any?(references, &asset_extension?(&1, [".js", ".mjs"])) and
        Enum.any?(references, &asset_extension?(&1, [".css"])) and
        Enum.all?(references, &asset_present?(root, &1))
    else
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp read_index(path) do
    File.open(path, [:read, :binary], &IO.binread(&1, @max_index_bytes + 1))
  end

  defp external_reference?(reference) do
    String.starts_with?(reference, ["https://", "http://", "//"])
  end

  defp asset_extension?(reference, extensions) do
    Path.extname(URI.parse(reference).path || "") in extensions
  end

  defp asset_present?(root, reference) do
    path = URI.parse(reference).path || ""
    parts = path |> String.trim_leading("/") |> String.split("/")

    case parts do
      ["assets" | [_ | _]] ->
        byte_size(path) <= 512 and length(parts) <= 8 and
          Enum.all?(parts, fn part ->
            part not in [".", ".."] and Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, part)
          end) and regular_path?(root, parts, @max_asset_bytes)

      _ ->
        false
    end
  end

  # Reject symlinks at every component, including the static root. Only own
  # packaged files count, never the retained/historical asset volume.
  defp regular_path?(root, parts, max_bytes) do
    with {:ok, %{type: :directory}} <- File.lstat(root) do
      walk_path(root, parts, max_bytes)
    else
      _ -> false
    end
  end

  defp walk_path(root, [file], max_bytes) do
    case File.lstat(Path.join(root, file)) do
      {:ok, %{type: :regular, size: size}} -> size > 0 and size <= max_bytes
      _ -> false
    end
  end

  defp walk_path(root, [directory | rest], max_bytes) do
    path = Path.join(root, directory)

    case File.lstat(path) do
      {:ok, %{type: :directory}} -> walk_path(path, rest, max_bytes)
      _ -> false
    end
  end
end
