defmodule Atlas.ImageFixtures do
  @moduledoc false
  alias Vix.Vips.{Image, MutableImage, Operation}

  def solid(width, height, color) do
    {:ok, black} = Operation.black(width, height)
    {:ok, img} = Operation.linear(black, [1, 1, 1], color)
    {:ok, img} = Operation.cast(img, :VIPS_FORMAT_UCHAR)
    {:ok, img} = Operation.copy(img, interpretation: :VIPS_INTERPRETATION_sRGB)
    img
  end

  def encode(img, suffix) do
    {:ok, bin} = Image.write_to_buffer(img, suffix)
    bin
  end

  def png(width \\ 64, height \\ 48), do: encode(solid(width, height, [255, 0, 0]), ".png")

  # Two 64x48 frames stacked into one 64x96 image with page-height set.
  def animated(suffix) do
    {:ok, stacked} =
      Operation.arrayjoin([solid(64, 48, [255, 0, 0]), solid(64, 48, [0, 255, 0])], across: 1)

    {:ok, stacked} = Operation.copy(stacked, [])
    {:ok, stacked} = Image.mutate(stacked, &MutableImage.set(&1, "page-height", :gint, 48))
    encode(stacked, suffix)
  end

  def svg(width \\ 120, height \\ 80) do
    ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}"><rect width="#{width}" height="#{height}" fill="blue"/></svg>)
  end
end
