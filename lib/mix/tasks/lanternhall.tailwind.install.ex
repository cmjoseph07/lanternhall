defmodule Mix.Tasks.Lanternhall.Tailwind.Install do
  @shortdoc "Installs the Tailwind binary and checks it against its pinned SHA-256"

  @moduledoc """
  Installs the Tailwind binary and checks it against the SHA-256 pinned for this machine's
  platform in `config/config.exs` (`config :lanternhall, :tailwind_sha256`).

      mix lanternhall.tailwind.install
      mix lanternhall.tailwind.install BASE_URL

  A binary already in place with the pinned hash is kept, and nothing is downloaded or
  run. Any other is downloaded again. A download with another hash is deleted and the
  task fails, so no build step runs a binary the repo did not pin. `BASE_URL` names a
  mirror, in the form `mix tailwind.install` takes.

  The `tailwind` package checks no hash: it downloads a release file from GitHub and
  runs it. So `mix assets.setup`, `assets.build` and `assets.deploy` run this task before
  they run Tailwind, and the dev watcher goes through `install_and_run/2`. `mix
  tailwind.install`, and `mix tailwind` with no binary in place, still download without
  a check; use neither.
  """
  use Mix.Task

  @impl Mix.Task
  def run([]), do: install(Tailwind.default_base_url())
  def run([base_url]), do: install(base_url)
  def run(_args), do: Mix.raise("usage: mix lanternhall.tailwind.install [BASE_URL]")

  @doc """
  Runs Tailwind for `profile` with `args` once the binary is installed and checked.

  The dev watcher (`config/dev.exs`) calls this in place of `Tailwind.install_and_run/2`.
  A binary that fails the check is reported and Tailwind is not run. The function then
  returns instead of raising: Phoenix starts a watcher that raised again every two
  seconds, and each start would download the binary once more.
  """
  def install_and_run(profile, args) do
    run([])
    Tailwind.run(profile, args)
  rescue
    error in Mix.Error ->
      Mix.shell().error(Exception.message(error))
      :error
  end

  defp install(base_url) do
    path = Tailwind.bin_path()
    pinned = pinned_sha256!()

    case sha256(path) do
      ^pinned ->
        :ok

      in_place ->
        if in_place do
          Mix.shell().info("The Tailwind binary at #{path} is not the pinned one; replacing it")
        end

        download(base_url)
        refuse_unless_pinned!(path, pinned)
    end
  end

  defp pinned_sha256! do
    target = Tailwind.configured_target()

    case Application.fetch_env!(:lanternhall, :tailwind_sha256) do
      %{^target => sha256} ->
        sha256

      _other ->
        Mix.raise(
          "No SHA-256 is pinned for the Tailwind binary of this platform (#{target}). " <>
            "Add it to :tailwind_sha256 in config/config.exs."
        )
    end
  end

  defp download(base_url) do
    # Mix keeps only the project's own applications on the code path.
    Mix.ensure_application!(:inets)
    Mix.ensure_application!(:ssl)
    Tailwind.install(base_url)
  end

  defp refuse_unless_pinned!(path, pinned) do
    case sha256(path) do
      ^pinned ->
        :ok

      downloaded ->
        File.rm!(path)

        Mix.raise("""
        The Tailwind #{Tailwind.configured_version()} binary for #{Tailwind.configured_target()} \
        is not the pinned one, and was deleted.

          downloaded SHA-256: #{downloaded}
          pinned SHA-256:     #{pinned}

        If the Tailwind version changed, set :tailwind_sha256 in config/config.exs from the
        sha256sums.txt of that release.
        """)
    end
  end

  # The binary is about 80 MB: hashed in chunks, never held in memory whole.
  defp sha256(path) do
    if File.regular?(path) do
      path
      |> File.stream!(1_048_576)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    end
  end
end
