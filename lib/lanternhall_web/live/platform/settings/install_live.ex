defmodule LanternhallWeb.Platform.Settings.InstallLive do
  @moduledoc """
  Settings > Install: the install config this node booted with, the versions it runs
  and how long it has been up (SPEC-platform.md section 3.6).
  """
  use LanternhallWeb, :live_view

  alias Lanternhall.Platform.Config

  @tick :timer.minutes(1)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Settings",
       config: Config.get(),
       serving_port: LanternhallWeb.Endpoint.config(:http)[:port],
       versions: versions()
     )
     |> assign_uptime()
     |> tick_while_connected()}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign_uptime(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Settings</h1>

      <section id="install" aria-labelledby="install-heading" class="space-y-3">
        <h2 id="install-heading" class="text-sm font-semibold text-base-content/70">Install</h2>
        <dl class="grid grid-cols-[8rem_minmax(0,1fr)] gap-x-4 gap-y-2 rounded-box bg-base-200 p-4 text-sm">
          <.fact id="install-kind" label="Kind" mono>{@config.kind}</.fact>
          <.fact id="install-port" label="Port" mono>
            {@config.port}
            <span :if={@serving_port != @config.port} class="font-sans text-base-content/70">
              (prod only; this server uses <span id="install-serving-port">{@serving_port}</span>)
            </span>
          </.fact>
          <.fact id="install-time-zone" label="Time zone" mono>{@config.time_zone}</.fact>
          <.fact id="install-data-dir" label="Data directory" mono>
            <.path value={@config.data_dir} />
          </.fact>
          <.fact id="install-config-path" label="Config file" mono>
            <.path value={@config.path} />
          </.fact>
          <.fact id="install-modules" label="Modules">
            <%= if @config.modules == [] do %>
              <span class="text-base-content/70">None</span>
            <% else %>
              <span class="font-mono">{Enum.join(@config.modules, ", ")}</span>
            <% end %>
          </.fact>
        </dl>
      </section>

      <section id="runtime" aria-labelledby="runtime-heading" class="space-y-3">
        <h2 id="runtime-heading" class="text-sm font-semibold text-base-content/70">Runtime</h2>
        <dl class="grid grid-cols-[8rem_minmax(0,1fr)] gap-x-4 gap-y-2 rounded-box bg-base-200 p-4 text-sm">
          <.fact :for={{id, label, version} <- @versions} id={id} label={label} mono>
            {version}
          </.fact>
          <.fact id="uptime" label="Uptime">{@uptime}</.fact>
        </dl>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :mono, :boolean, default: false
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <div class="contents">
      <dt class="text-base-content/70">{@label}</dt>
      <dd id={@id} class={["break-words", @mono && "font-mono"]}>{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :value, :string, required: true

  # Long paths wrap after a slash, never inside a directory name.
  defp path(assigns) do
    assigns = assign(assigns, :parts, String.split(assigns.value, ~r{(?<=/)}))

    ~H"""
    <span :for={part <- @parts}>{part}<wbr /></span>
    """
  end

  @doc """
  Formats a duration in milliseconds in its largest two units, for example `"3 d 4 h"`.
  """
  @spec format_uptime(non_neg_integer()) :: String.t()
  def format_uptime(milliseconds) do
    minutes = div(milliseconds, :timer.minutes(1))
    {hours, minutes} = {div(minutes, 60), rem(minutes, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    cond do
      days > 0 -> "#{days} d #{hours} h"
      hours > 0 -> "#{hours} h #{minutes} min"
      minutes > 0 -> "#{minutes} min"
      true -> "under a minute"
    end
  end

  defp tick_while_connected(socket) do
    if connected?(socket) do
      {:ok, _ref} = :timer.send_interval(@tick, :tick)
      socket
    else
      socket
    end
  end

  # Time since the BEAM node started, which is the app's uptime in a release.
  defp assign_uptime(socket) do
    {milliseconds, _since_last_call} = :erlang.statistics(:wall_clock)
    assign(socket, uptime: format_uptime(milliseconds))
  end

  defp versions do
    [
      {"version-app", "Lanternhall", Lanternhall.version()},
      {"version-elixir", "Elixir", System.version()},
      {"version-otp", "Erlang/OTP", otp_version()},
      {"version-phoenix", "Phoenix", app_version(:phoenix)},
      {"version-live-view", "LiveView", app_version(:phoenix_live_view)}
    ]
  end

  defp app_version(app), do: to_string(Application.spec(app, :vsn))

  # `System.otp_release/0` gives only the major version; the full one is in a file.
  # The path is built from the runtime's own root and release, never from input.
  # sobelow_skip ["Traversal.FileModule"]
  defp otp_version do
    path = Path.join([:code.root_dir(), "releases", System.otp_release(), "OTP_VERSION"])

    case File.read(path) do
      {:ok, version} -> String.trim(version)
      {:error, _} -> System.otp_release()
    end
  end
end
