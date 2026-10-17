defmodule Atlas.Accounts.User.Validations.Avatar do
  use Ash.Resource.Validation

  @max_bytes 512 * 1024

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :avatar) do
      nil -> :ok
      avatar -> validate_avatar(avatar)
    end
  end

  defp validate_avatar(avatar) do
    with [prefix, encoded] <- String.split(avatar, ",", parts: 2),
         true <- byte_size(encoded) <= 699_052,
         {:ok, bytes} <- Base.decode64(encoded),
         true <- byte_size(bytes) <= @max_bytes,
         true <- image?(prefix, bytes) do
      :ok
    else
      _ -> {:error, field: :avatar, message: "must be a PNG, JPEG, or WebP image up to 512 KB"}
    end
  end

  defp image?("data:image/png;base64", <<137, "PNG\r\n", 26, 10, _::binary>>), do: true
  defp image?("data:image/jpeg;base64", <<255, 216, 255, _::binary>>), do: true

  defp image?("data:image/webp;base64", <<"RIFF", _::binary-size(4), "WEBP", _::binary>>),
    do: true

  defp image?(_, _), do: false
end
