defmodule AtlasWeb.Plugs.Frontend do
  @moduledoc """
  Opt-in delivery of the release's public frontend, without claiming backend routes.

  The packaged static directory is the only source of HTML and root public files.
  The optional retained directory contains asset filenames, mounted only at /assets.
  Explicit init options allow isolated tests without a frontend build or global config.
  """
  @behaviour Plug

  import Plug.Conn

  @reserved ~w(.well-known api auth rpc mcp oauth socket health dev ash_ai)
  @immutable "public, max-age=31536000, immutable"

  @impl true
  def init(opts) do
    %{
      serve_frontend: Keyword.get(opts, :serve_frontend, :runtime),
      static_dir: Keyword.get(opts, :static_dir),
      asset_dir: Keyword.get(opts, :asset_dir, :runtime)
    }
  end

  @impl true
  def call(conn, opts) do
    enabled? =
      case opts.serve_frontend do
        :runtime -> Application.get_env(:atlas, :serve_frontend, false)
        value -> value
      end

    if enabled? == true and conn.method in ["GET", "HEAD"] do
      deliver(conn, opts)
    else
      conn
    end
  end

  defp deliver(conn, opts) do
    # Decode before checking reserved prefixes and filesystem components. Never let
    # encoded separators, traversal, hidden files or symlinks escape the public root.
    parts = Enum.map(conn.path_info, &URI.decode/1)

    cond do
      List.first(parts) in @reserved ->
        conn

      not Enum.all?(parts, &safe_component?/1) ->
        not_found(conn)

      true ->
        root = opts.static_dir || Application.app_dir(:atlas, "priv/static")
        deliver_public(conn, parts, root, opts)
    end
  end

  defp deliver_public(conn, ["assets" | rest] = parts, root, opts) do
    retained =
      case opts.asset_dir do
        :runtime -> Application.get_env(:atlas, :frontend_asset_dir)
        value -> value
      end

    file =
      public_file(root, parts) ||
        if retained_asset?(rest), do: public_file(retained, rest)

    case file do
      nil -> not_found(conn)
      path -> serve(conn, path, :asset)
    end
  end

  defp deliver_public(conn, parts, root, _opts) do
    cond do
      file = public_file(root, parts) ->
        serve(conn, file, :public)

      page_path?(parts) and accepts_html?(conn) ->
        case public_file(root, ["index.html"]) do
          nil -> not_found(conn)
          path -> serve(conn, path, :public)
        end

      true ->
        not_found(conn)
    end
  end

  defp safe_component?(part) do
    String.valid?(part) and part != "" and not String.starts_with?(part, ".") and
      not String.contains?(part, ["/", "\\", <<0>>])
  end

  # Signed auth tokens contain dots but are application routes, not filenames.
  defp page_path?([page, _token])
       when page in ~w(confirm_new_user password-reset claim join),
       do: true

  # Other URLs that look like files must never silently become the SPA shell.
  defp page_path?(parts), do: Enum.all?(parts, &(Path.extname(&1) == ""))

  # Match deploy/publish-assets: every path component is a public ASCII name,
  # and the final filename has a Vite fingerprint and an allowed public extension.
  # Packaged files intentionally bypass this policy and always take precedence.
  defp retained_asset?(parts) do
    parts != [] and
      Enum.all?(parts, &Regex.match?(~r/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/, &1)) and
      Regex.match?(
        ~r/-[A-Za-z0-9_-]{8,}\.(js|mjs|css|woff2?|ttf|otf|eot|svg|png|jpe?g|gif|webp|avif|ico|wasm|json|mp3|mp4|ogg|webm)\z/,
        List.last(parts)
      )
  end

  defp html_path?(parts) do
    parts != [] and
      String.downcase(Path.extname(List.last(parts))) in [".html", ".htm", ".xhtml", ".shtml"]
  end

  defp public_file(root, _parts) when root in [nil, ""], do: nil
  defp public_file(_root, []), do: nil

  defp public_file(root, parts) do
    # Check every component, not just the final file: a symlinked directory is
    # just as unsafe as a symlinked file. Roots are trusted release configuration.
    with :absolute <- Path.type(root),
         {:ok, %{type: :directory}} <- File.lstat(root) do
      parts
      |> Enum.with_index(1)
      |> Enum.reduce_while(root, fn {part, index}, parent ->
        path = Path.join(parent, part)
        expected = if index == length(parts), do: :regular, else: :directory

        case File.lstat(path) do
          {:ok, %{type: ^expected}} -> {:cont, path}
          _ -> {:halt, nil}
        end
      end)
    else
      _ -> nil
    end
  end

  defp accepts_html?(conn) do
    case get_req_header(conn, "accept") do
      [] ->
        true

      headers ->
        # Specific exclusions win over wildcards (text/html;q=0, */*).
        {_, quality} =
          headers
          |> Enum.flat_map(&String.split(&1, ","))
          |> Enum.map(&html_quality/1)
          |> Enum.max(fn -> {-1, 0.0} end)

        quality > 0
    end
  end

  defp html_quality(range) do
    case Plug.Conn.Utils.media_type(String.trim(range)) do
      {:ok, type, subtype, params} ->
        specificity =
          case {type, subtype} do
            {"text", "html"} -> 2
            {"text", "*"} -> 1
            {"*", "*"} -> 0
            _ -> -1
          end

        quality =
          case Float.parse(Map.get(params, "q", "1")) do
            {q, ""} when q >= 0 and q <= 1 -> q
            _ -> 0.0
          end

        {specificity, if(specificity >= 0, do: quality, else: 0.0)}

      _ ->
        {-1, 0.0}
    end
  end

  defp serve(conn, path, kind) do
    mime = MIME.from_path(path)
    cache = if kind == :asset and not html_path?([path]), do: @immutable, else: "no-cache"
    size = File.stat!(path).size

    conn =
      conn
      |> response_headers(cache)
      |> put_resp_content_type(mime)
      |> put_resp_header("content-length", Integer.to_string(size))

    conn =
      if conn.method == "HEAD" do
        send_resp(conn, 200, "")
      else
        send_file(conn, 200, path)
      end

    halt(conn)
  end

  defp not_found(conn) do
    # Keep the API's existing JSON error shape even for missing public files.
    body = ~s({"errors":{"detail":"Not Found"}})

    conn
    |> response_headers("no-store")
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-length", Integer.to_string(byte_size(body)))
    |> send_resp(404, if(conn.method == "HEAD", do: "", else: body))
    |> halt()
  end

  defp response_headers(conn, cache) do
    vary = get_resp_header(conn, "vary") |> Enum.join(", ")

    vary =
      if Enum.any?(
           String.split(vary, ","),
           &(String.downcase(String.trim(&1)) in ["accept", "*"])
         ) do
        vary
      else
        if vary == "", do: "Accept", else: vary <> ", Accept"
      end

    conn
    |> put_resp_header("cache-control", cache)
    |> put_resp_header("vary", vary)
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "SAMEORIGIN")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
  end
end
