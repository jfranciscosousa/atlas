defmodule Atlas.Storage.R2 do
  @moduledoc """
  Cloudflare R2 adapter (S3 API). Configured at runtime from environment variables.
  """
  @behaviour Atlas.Storage

  @impl true
  def put(key, body, content_type) do
    config = config()

    response =
      Req.new(retry: :transient)
      |> ReqS3.attach()
      |> Req.put(
        url: "s3://#{config[:bucket]}/#{key}",
        body: body,
        headers: [{"content-type", content_type}],
        aws_endpoint_url_s3: config[:endpoint_url],
        aws_sigv4: sigv4(config)
      )

    case response do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:r2_status, status}}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def signed_url(key, ttl_seconds) do
    config = config()

    ReqS3.presign_url(
      [
        bucket: config[:bucket],
        key: key,
        endpoint_url: config[:endpoint_url],
        expires: ttl_seconds
      ] ++
        sigv4(config)
    )
  end

  defp sigv4(config) do
    [
      access_key_id: config[:access_key_id],
      secret_access_key: config[:secret_access_key],
      region: "auto"
    ]
  end

  defp config, do: Application.fetch_env!(:atlas, Atlas.Storage)
end
