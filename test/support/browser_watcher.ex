defmodule LanternhallWeb.BrowserWatcher do
  @moduledoc false
  use GenServer

  alias PhoenixTest.Playwright
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Frame

  def start(conn), do: GenServer.start(__MODULE__, conn)

  def stop(watcher), do: GenServer.stop(watcher)

  def errors(watcher) do
    watcher |> GenServer.call(:frames) |> Enum.each(&round_trip/1)
    GenServer.call(watcher, :errors)
  end

  @impl true
  def init(conn) do
    :ok = PlaywrightEx.subscribe(conn.context_id)

    {:ok, _} =
      BrowserContext.update_subscription(conn.context_id, event: :console, timeout: timeout())

    {:ok, %{frames: [conn.frame_id], errors: []}}
  end

  @impl true
  def handle_call(:frames, _from, state), do: {:reply, state.frames, state}
  def handle_call(:errors, _from, state), do: {:reply, Enum.reverse(state.errors), state}

  @impl true
  def handle_info({:playwright_msg, message}, state), do: {:noreply, record(message, state)}

  defp record(
         %{
           method: :__create__,
           params: %{type: "Page", initializer: %{main_frame: %{guid: frame_id}}}
         },
         state
       ) do
    %{state | frames: [frame_id | state.frames]}
  end

  defp record(%{method: :console, params: %{type: "error", text: text}}, state) do
    %{state | errors: [text | state.errors]}
  end

  defp record(%{method: :page_error, params: %{error: %{error: error}}}, state) do
    %{state | errors: ["#{error[:name]}: #{error[:message]}" | state.errors]}
  end

  defp record(%{method: :page_error, params: params}, state) do
    %{state | errors: [inspect(params) | state.errors]}
  end

  defp record(_message, state), do: state

  # Playwright answers a call to a page after the events that page sent before it.
  defp round_trip(frame_id), do: Frame.evaluate(frame_id, expression: "0", timeout: timeout())

  defp timeout, do: Playwright.Config.global(:timeout)
end
