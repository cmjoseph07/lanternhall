defmodule LanternhallWeb.Brand.LogoSvgTest do
  # The logo SVGs are hand-written (SPEC-platform.md section 3.8): no fonts, no raster images,
  # no inline `style` (CSP forbids it, section 3.3), nothing loaded from elsewhere.
  use ExUnit.Case, async: true

  require Record

  # Mix prunes OTP apps that are not dependencies from the code path; xmerl ships with OTP.
  Mix.ensure_application!(:xmerl)

  Record.defrecordp(
    :element,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :attr,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @images "priv/static/images"
  @svg_ns :"http://www.w3.org/2000/svg"

  # Elements that would pull in a font, a raster, a script, CSS or another document.
  @forbidden ~w(text tspan textPath font font-face image foreignObject style script use a)

  for name <- ["logo.svg", "logo-mark.svg"] do
    describe name do
      setup do
        %{root: parse(unquote(name))}
      end

      test "is a well-formed SVG document with a viewBox", %{root: root} do
        assert element(root, :expanded_name) == {@svg_ns, :svg}
        assert [_x, _y, w, h] = viewbox(root)
        assert w > 0 and h > 0
      end

      test "uses no fonts, rasters, scripts, CSS or external references", %{root: root} do
        assert offences(root) == []
      end
    end
  end

  test "logo-mark.svg is square, ready to render icons from" do
    assert [_x, _y, size, size] = viewbox(parse("logo-mark.svg"))
  end

  defp parse(name) do
    {root, []} =
      @images
      |> Path.join(name)
      |> File.read!()
      |> String.to_charlist()
      |> :xmerl_scan.string(namespace_conformant: true, quiet: true)

    root
  end

  defp viewbox(root) do
    root
    |> attribute_value(:viewBox)
    |> String.split()
    |> Enum.map(&(&1 |> Float.parse() |> elem(0)))
  end

  defp attribute_value(el, name) do
    Enum.find_value(
      element(el, :attributes),
      &(attr(&1, :name) == name && to_string(attr(&1, :value)))
    )
  end

  defp offences(el) do
    tag = to_string(element(el, :name))
    own = if tag in @forbidden, do: ["<#{tag}> is forbidden"], else: []

    attrs =
      for a <- element(el, :attributes),
          offence = attribute_offence(to_string(attr(a, :name)), to_string(attr(a, :value))),
          do: "<#{tag}> #{offence}"

    children = for child <- element(el, :content), Record.is_record(child, :xmlElement), do: child
    own ++ attrs ++ Enum.flat_map(children, &offences/1)
  end

  defp attribute_offence("style", _value), do: "has an inline style attribute"
  defp attribute_offence("font" <> _ = name, _value), do: "sets #{name}"

  defp attribute_offence(name, _value) when name in ["href", "xlink:href"],
    do: "references #{name}"

  defp attribute_offence(name, value) do
    if value =~ ~r/url\(|data:/, do: "#{name} references another resource"
  end
end
