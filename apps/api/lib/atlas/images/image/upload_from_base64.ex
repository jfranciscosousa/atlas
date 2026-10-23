defmodule Atlas.Images.Image.UploadFromBase64 do
  @moduledoc """
  Stores an image that the client sends as base64 text, with the same rights check, type check
  and WebP conversion as an upload from the web app. A `data:...;base64,` prefix is accepted.
  The JSON body limit of the endpoint (8 MB) is the real size limit, so an image can be about
  6 MB here. A larger image needs `upload_from_url`.
  """
  use Ash.Resource.Actions.Implementation

  alias Atlas.Images.Image.UploadFromUrl

  @max_text 8_000_000

  @impl true
  def run(input, _opts, %{actor: actor}) do
    text = String.replace(input.arguments.data, ~r/\A\s*data:[^,]*,/, "")

    with true <- byte_size(text) <= @max_text || {:error, "is larger than about 6 MB"},
         {:ok, binary} <-
           Base.decode64(text, ignore: :whitespace, padding: false) |> or_error("is not base64") do
      path = Path.join(System.tmp_dir!(), "base64-#{Ecto.UUID.generate()}")
      File.write!(path, binary)
      UploadFromUrl.store(actor, path, :data)
    else
      {:error, message} -> {:error, UploadFromUrl.error(:data, message)}
    end
  end

  defp or_error(:error, message), do: {:error, message}
  defp or_error(ok, _message), do: ok
end
