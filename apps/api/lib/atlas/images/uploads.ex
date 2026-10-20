defmodule Atlas.Images.Uploads do
  @moduledoc """
  Accepts an image for one section of a campaign, a note, or a session. Authorization comes
  first, so an unauthorized caller never costs image-processing time or storage.
  """

  alias Atlas.Images.{Image, Parent, Processor}

  @spec upload_image(Atlas.Accounts.User.t(), String.t(), String.t(), String.t(), Path.t()) ::
          {:ok, Image.t()} | {:error, :not_found | Processor.error()}
  def upload_image(actor, parent_path, parent_id, section_name, path) do
    with {:ok, kind} <- Parent.from_path(parent_path) |> or_not_found(),
         {:ok, section} <- section(kind, section_name),
         {:ok, parent} <- fetch_parent(kind, parent_id, actor),
         true <- Ash.can?({parent, :"save_#{section}"}, actor) || {:error, :not_found},
         :ok <- check_size(path),
         {:ok, processed} <- path |> File.read!() |> Processor.process(),
         key = "images/#{Ecto.UUID.generate()}.webp",
         :ok <- Atlas.Storage.put(key, processed.webp, "image/webp") do
      Ash.create(
        Image,
        %{
          parent_type: kind,
          parent_id: parent.id,
          section: section,
          storage_key: key,
          byte_size: byte_size(processed.webp),
          width: processed.width,
          height: processed.height,
          animated: processed.animated?
        },
        actor: actor
      )
    end
  end

  defp or_not_found(:error), do: {:error, :not_found}
  defp or_not_found(ok), do: ok

  # Compare strings so a client can never mint atoms.
  defp section(kind, name) do
    case Enum.find(
           Atlas.RichText.sections(Parent.module(kind)),
           &(Atom.to_string(&1) == name)
         ) do
      nil -> {:error, :not_found}
      section -> {:ok, section}
    end
  end

  defp fetch_parent(kind, id, actor) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Ash.get(Parent.module(kind), uuid, actor: actor) do
          {:ok, parent} -> {:ok, parent}
          {:error, _} -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: 0}} ->
        {:error, :unsupported_type}

      {:ok, %{size: size}} ->
        if size <= Processor.max_bytes(), do: :ok, else: {:error, :too_large}

      _ ->
        {:error, :unreadable}
    end
  end
end
