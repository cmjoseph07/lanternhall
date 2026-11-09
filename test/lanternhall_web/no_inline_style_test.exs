defmodule LanternhallWeb.NoInlineStyleTest do
  use ExUnit.Case, async: true

  # A `style=` attribute would need CSP `style-src 'unsafe-inline'` (SPEC-platform.md section 3.3).
  test "no template under lib/lanternhall_web has an inline style attribute" do
    offenders =
      for path <- Path.wildcard("lib/lanternhall_web/**/*.{ex,heex}"),
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ ~r/\sstyle=/,
          do: "#{path}:#{number}"

    assert offenders == []
  end
end
