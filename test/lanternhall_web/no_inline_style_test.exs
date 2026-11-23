defmodule LanternhallWeb.NoInlineStyleTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)

  test "no template under lib/lanternhall_web has an inline style attribute" do
    paths = Path.wildcard(Path.join(@repo_root, "lib/lanternhall_web/**/*.{ex,heex}"))

    assert paths != []

    offenders =
      for path <- paths,
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ ~r/\sstyle=/,
          do: "#{Path.relative_to(path, @repo_root)}:#{number}"

    assert offenders == []
  end
end
