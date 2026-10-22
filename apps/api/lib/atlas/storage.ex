defmodule Atlas.Storage do
  @moduledoc """
  Private object storage for converted images.

  Objects are never public. Callers issue short-lived signed URLs, and only after the API
  has checked current access to the section that contains the image.
  """

  @callback put(key :: String.t(), body :: binary, content_type :: String.t()) ::
              :ok | {:error, term}

  @callback delete(key :: String.t()) :: :ok | {:error, term}

  @callback signed_url(key :: String.t(), ttl_seconds :: pos_integer) :: String.t()

  @ttl_seconds 600

  def ttl_seconds, do: @ttl_seconds

  def put(key, body, content_type), do: adapter().put(key, body, content_type)
  def delete(key), do: adapter().delete(key)
  def signed_url(key), do: adapter().signed_url(key, @ttl_seconds)

  defp adapter, do: Application.fetch_env!(:atlas, __MODULE__) |> Keyword.fetch!(:adapter)
end
