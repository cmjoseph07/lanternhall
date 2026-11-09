defmodule LanternhallWeb.Brand.IconsTest do
  # The favicon and PWA icons are generated from logo-mark.svg by
  # `pnpm --dir assets run icons` and committed (SPEC-platform.md section 3.8).
  use ExUnit.Case, async: true

  @images "priv/static/images"

  # The touch icon and the maskable icon fill their square: iOS and the platform
  # masks would show any transparent pixel as black, so they carry no alpha channel.
  @pngs [
    {"favicon-32.png", 32, :rgba},
    {"icon-192.png", 192, :rgba},
    {"icon-512.png", 512, :rgba},
    {"apple-touch-icon.png", 180, :rgb},
    {"icon-maskable-512.png", 512, :rgb}
  ]

  for {name, size, color} <- @pngs do
    test "#{name} is a #{size} x #{size} #{color} PNG" do
      assert png_header(unquote(name)) == {unquote(size), unquote(size), unquote(color)}
    end
  end

  test "favicon.svg is logo-mark.svg without its comments" do
    mark = File.read!(Path.join(@images, "logo-mark.svg"))
    expected = String.replace(mark, ~r/\n?\s*<!--.*?-->/s, "")

    assert File.read!(Path.join(@images, "favicon.svg")) == expected
    refute expected =~ "<!--"
  end

  # A PNG starts with an 8-byte signature and the IHDR chunk: width, height,
  # bit depth and color type (2 = truecolor, 6 = truecolor with alpha).
  defp png_header(name) do
    <<137, "PNG\r\n", 26, "\n", 13::32, "IHDR", width::32, height::32, 8, color_type, _::binary>> =
      File.read!(Path.join(@images, name))

    {width, height, Map.fetch!(%{2 => :rgb, 6 => :rgba}, color_type)}
  end
end
