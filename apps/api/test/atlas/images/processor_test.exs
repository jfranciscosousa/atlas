defmodule Atlas.Images.ProcessorTest do
  use ExUnit.Case, async: true

  alias Atlas.Images.Processor
  import Atlas.ImageFixtures

  alias Vix.Vips.{Image, Operation}

  defp webp_info(webp) do
    {:ok, {img, _flags}} = Operation.webpload_buffer(webp, n: -1)
    {Image.width(img), Image.height(img), Image.header_value(img, "n-pages")}
  end

  test "every accepted format becomes a WebP with the same dimensions" do
    red = solid(64, 48, [255, 0, 0])

    for {label, bin} <- [
          jpeg: encode(red, ".jpg"),
          png: encode(red, ".png"),
          webp: encode(red, ".webp"),
          gif: encode(red, ".gif"),
          avif: encode(red, ".avif")
        ] do
      assert {:ok, %{webp: webp, width: 64, height: 48, animated?: false}} =
               Processor.process(bin),
             "#{label}"

      assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = webp
    end
  end

  test "a GIF animation survives as an animated WebP" do
    assert {:ok, %{webp: webp, width: 64, height: 48, animated?: true}} =
             Processor.process(animated(".gif"))

    assert {64, 96, {:ok, 2}} = webp_info(webp)
  end

  test "an SVG is rasterized, keeping its size" do
    svg =
      ~s(<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="blue"/></svg>)

    assert {:ok, %{webp: webp, width: 120, height: 80, animated?: false}} = Processor.process(svg)
    assert {120, 80, _} = webp_info(webp)
  end

  test "an SVG with external references is rejected" do
    for svg <- [
          ~s(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="9" height="9"><image xlink:href="file:///etc/hostname" width="9" height="9"/></svg>),
          ~s(<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg xmlns="http://www.w3.org/2000/svg" width="9" height="9">&x;</svg>)
        ] do
      assert {:error, :unsafe_svg} = Processor.process(svg)
    end
  end

  test "the real file type decides, not the extension or claimed type" do
    assert {:error, :unsupported_type} = Processor.process("%PDF-1.7 hello")
    assert {:error, :unsupported_type} = Processor.process("<html><svg></svg></html>")
    assert {:error, :unsupported_type} = Processor.process(<<"II*", 0, 1, 2, 3>>)
    assert {:error, :unsupported_type} = Processor.process("")
  end

  test "a truncated or corrupt image is unreadable" do
    png = encode(solid(64, 48, [1, 2, 3]), ".png")
    assert {:error, :unreadable} = Processor.process(binary_part(png, 0, 40))

    assert {:error, :unreadable} =
             Processor.process(<<0x89, "PNG\r\n", 0x1A, "\n", 0::size(800)>>)
  end

  test "files over 25 MB are rejected before any decoding" do
    assert {:error, :too_large} = Processor.process(:binary.copy(<<0xFF, 0xD8, 0xFF>>, 9_000_000))
  end

  test "images over the pixel limits are rejected from the header" do
    # 7000 x 7001 = 49.007 MP is fine; 7100 x 7100 = 50.41 MP is over the per-frame limit.
    assert {:ok, _} = Processor.process(encode(solid(7000, 7000, [0, 0, 0]), ".png"))

    assert {:error, :too_many_pixels} =
             Processor.process(encode(solid(7100, 7100, [0, 0, 0]), ".png"))

    assert {:error, :too_many_pixels} =
             Processor.process(encode(solid(16_384, 8, [0, 0, 0]), ".png"))
  end

  test "an SVG that declares a huge size is rejected" do
    svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" width="30000" height="30000"></svg>)
    assert {:error, :too_many_pixels} = Processor.process(svg)
  end
end
