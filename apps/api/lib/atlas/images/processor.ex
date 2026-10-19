defmodule Atlas.Images.Processor do
  @moduledoc """
  Validates an uploaded image and converts it to optimized WebP.

  The real file type is sniffed from the bytes, never taken from the client. Size limits are
  checked from the image header before any pixel is decoded. GIF animation is kept as animated
  WebP, SVG is rasterized, and all metadata is stripped.
  """

  alias Vix.Vips.{Image, Operation}

  @max_bytes 25 * 1024 * 1024
  # WebP cannot encode a side longer than 16383 px.
  @max_side 16_383
  @max_frame_pixels 50_000_000
  @max_total_pixels 100_000_000
  @max_frames 200
  @timeout :timer.seconds(30)
  @quality 85

  @type result :: %{
          webp: binary,
          width: pos_integer,
          height: pos_integer,
          animated?: boolean
        }

  @type error ::
          :too_large | :unsupported_type | :unsafe_svg | :too_many_pixels | :unreadable | :timeout

  def max_bytes, do: @max_bytes

  @spec process(binary) :: {:ok, result} | {:error, error}
  def process(binary) when byte_size(binary) > @max_bytes, do: {:error, :too_large}

  def process(binary) do
    case sniff(binary) do
      nil -> {:error, :unsupported_type}
      type -> run(type, binary)
    end
  end

  # shortcut: killing the task does not stop a running NIF, it only stops waiting for it.
  # Upgrade to an OS-level limit if untrusted-upload volume grows.
  defp run(type, binary) do
    task = Task.async(fn -> convert(type, binary) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :timeout}
    end
  end

  defp sniff(<<0xFF, 0xD8, 0xFF, _::binary>>), do: :jpeg
  defp sniff(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: :png
  defp sniff(<<"GIF8", v, "a", _::binary>>) when v in [?7, ?9], do: :gif
  defp sniff(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: :webp

  defp sniff(<<_::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>)
       when brand in ["avif", "avis"],
       do: :avif

  defp sniff(binary) do
    head = binary |> binary_part(0, min(byte_size(binary), 2048)) |> String.trim_leading("﻿")

    if head =~ ~r/\A\s*(<\?xml|<!--|<!DOCTYPE\s+svg|<svg[\s>])/i and head =~ ~r/<svg[\s>]/,
      do: :svg
  end

  defp convert(:svg, binary) do
    # External references would make the server fetch files or URLs while rendering.
    if binary =~ ~r/<!(DOCTYPE|ENTITY)|href\s*=\s*["'](?!#|data:)/i,
      do: {:error, :unsafe_svg},
      else: load(Operation.svgload_buffer(binary))
  end

  defp convert(:gif, binary), do: load(Operation.gifload_buffer(binary, n: -1))
  defp convert(:webp, binary), do: load(Operation.webpload_buffer(binary, n: -1))
  defp convert(:jpeg, binary), do: load(Operation.jpegload_buffer(binary))
  defp convert(:png, binary), do: load(Operation.pngload_buffer(binary))
  defp convert(:avif, binary), do: load(Operation.heifload_buffer(binary))

  # Loaders return the image together with its foreign-load flags.
  defp load({:ok, {image, _flags}}), do: finish(image)
  defp load(_), do: {:error, :unreadable}

  defp finish(image) do
    width = Image.width(image)
    height = Image.height(image)
    frames = frames(image)
    frame_height = div(height, frames)

    cond do
      frames > @max_frames or width > @max_side or frame_height > @max_side ->
        {:error, :too_many_pixels}

      width * frame_height > @max_frame_pixels or
          width * frame_height * frames > @max_total_pixels ->
        {:error, :too_many_pixels}

      true ->
        encode(image, width, frame_height, frames)
    end
  end

  defp frames(image) do
    case Image.header_value(image, "n-pages") do
      {:ok, n} when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  defp encode(image, width, height, frames) do
    with {:ok, image} <- prepare(image, frames),
         {:ok, webp} <- Image.write_to_buffer(image, ".webp[Q=#{@quality},strip]") do
      {:ok, %{webp: webp, width: width, height: height, animated?: frames > 1}}
    else
      _ -> {:error, :unreadable}
    end
  end

  defp prepare(image, 1) do
    with {:ok, {image, _rotation}} <- Operation.autorot(image) do
      Operation.colourspace(image, :VIPS_INTERPRETATION_sRGB)
    end
  end

  defp prepare(image, _frames), do: {:ok, image}
end
