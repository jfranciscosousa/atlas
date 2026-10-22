defmodule Atlas.Images.Fetch do
  @moduledoc """
  Downloads an image from a URL that a client names. The server then makes the request, so the
  URL must not reach the server's own network:

    * Only `http` and `https` URLs.
    * Every address of the host must be public. The request goes to the address that passed
      the check, so a DNS answer that changes later gains nothing.
    * No redirects: a redirect could point at a private address.
    * The body stops at the image size limit.

  Config `:image_fetch` takes `:resolver` and `:req_options`, for tests.
  """

  alias Atlas.Images.Processor

  @doc "Downloads the URL to a new temporary file and returns its path. The caller deletes it."
  @spec download(String.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def download(url) do
    with {:ok, uri} <- parse(url),
         {:ok, address} <- resolve(uri.host),
         {:ok, body} <- get(uri, address) do
      path = Path.join(System.tmp_dir!(), "fetch-#{Ecto.UUID.generate()}")
      File.write!(path, body)
      {:ok, path}
    end
  end

  defp parse(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, uri}

      _ ->
        {:error, "must be an http or https URL"}
    end
  end

  defp resolve(host) do
    resolver = config(:resolver, &lookup/1)

    case resolver.(host) do
      [first | _] = addresses ->
        if Enum.all?(addresses, &public?/1),
          do: {:ok, first},
          else: {:error, "must not point to a private address"}

      _ ->
        {:error, "has a host that does not resolve"}
    end
  end

  defp lookup(host) do
    charlist = String.to_charlist(host)

    for family <- [:inet, :inet6],
        {:ok, addresses} <- [:inet.getaddrs(charlist, family)],
        a <- addresses,
        do: a
  end

  defp get(uri, address) do
    max = Processor.max_bytes()

    options =
      [
        url: URI.to_string(%{uri | host: address |> :inet.ntoa() |> to_string()}),
        headers: [{"host", host_header(uri)}],
        connect_options: [hostname: uri.host, timeout: 5_000],
        redirect: false,
        retry: false,
        decode_body: false,
        receive_timeout: 15_000,
        into: fn {:data, data}, {request, response} ->
          chunks = Req.Response.get_private(response, :chunks, [])
          size = Req.Response.get_private(response, :size, 0) + byte_size(data)
          response = Req.Response.put_private(response, :size, size)

          if size > max do
            {:halt, {request, Req.Response.put_private(response, :too_large, true)}}
          else
            {:cont, {request, Req.Response.put_private(response, :chunks, [data | chunks])}}
          end
        end
      ] ++ config(:req_options, [])

    case Req.get(options) do
      {:ok, %Req.Response{private: %{too_large: true}}} ->
        {:error, "is larger than 25 MB"}

      {:ok, %Req.Response{status: 200} = response} ->
        {:ok,
         response
         |> Req.Response.get_private(:chunks, [])
         |> Enum.reverse()
         |> IO.iodata_to_binary()}

      {:ok, %Req.Response{status: status}} ->
        {:error, "answered with status #{status}"}

      {:error, _} ->
        {:error, "could not be downloaded"}
    end
  end

  defp host_header(%URI{host: host, port: port, scheme: scheme}) do
    default = if scheme == "https", do: 443, else: 80
    if port in [nil, default], do: host, else: "#{host}:#{port}"
  end

  defp config(key, default),
    do: :atlas |> Application.get_env(:image_fetch, []) |> Keyword.get(key, default)

  @doc false
  def public?({a, b, _, _}) do
    not (a in [0, 10, 127] or a >= 224 or (a == 100 and b in 64..127) or (a == 169 and b == 254) or
           (a == 172 and b in 16..31) or (a == 192 and b == 168) or (a == 192 and b == 0) or
           (a == 198 and b in 18..19))
  end

  # An IPv4 address inside IPv6 has the rules of the IPv4 address.
  def public?({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: public?({div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)})

  def public?({a, b, _, _, _, _, _, _}),
    do:
      not (a == 0 or a in 0xFC00..0xFDFF or a in 0xFE80..0xFEBF or a >= 0xFF00 or
             (a == 0x64 and b == 0xFF9B))
end
