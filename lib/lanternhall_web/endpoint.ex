defmodule LanternhallWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :lanternhall

  alias LanternhallWeb.Plugs.HostCheck
  alias LanternhallWeb.Plugs.SecurityHeaders
  alias LanternhallWeb.Plugs.SessionCookieCheck
  alias Plug.Conn.WrapperError

  # SameSite=Lax, not Strict: the session holds only the CSRF token, and Lax already
  # withholds it from cross-site POSTs and subrequests. Strict would also drop it when a
  # link on another site (mail, chat, calendar) opens the app, which starts a new session
  # and breaks the CSRF token of every tab already open.
  @session_options [
    store: :cookie,
    key: Application.compile_env!(:lanternhall, :session_cookie),
    signing_salt: "in+/Bvct",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  # Phoenix dispatches `socket` paths (LiveView, live reload) before the first `plug`
  # below, so the security headers and the two checks wrap the whole endpoint instead:
  # every response carries the headers, and every request, WebSocket upgrades included,
  # passes the checks first (SPEC-platform.md section 3.3).
  @before_dispatch [
    {SecurityHeaders, dev_tools: code_reloading?},
    {HostCheck, []},
    {SessionCookieCheck, key: @session_options[:key]}
  ]

  def call(conn, opts) do
    conn = Plug.run(conn, @before_dispatch)

    if conn.halted do
      conn
    else
      # Phoenix renders an error on the conn it gave `call/2`, which has none of the
      # headers set above, unless the error arrives wrapped with a conn of its own. The
      # router wraps the errors it raises; this wraps the rest (an endpoint plug refusing
      # the request, or an exit or throw from anywhere), so error responses carry the
      # headers too.
      try do
        super(conn, opts)
      catch
        kind, reason when not is_struct(reason, WrapperError) ->
          WrapperError.reraise(%WrapperError{
            conn: conn,
            kind: kind,
            reason: reason,
            stack: __STACKTRACE__
          })
      end
    end
  end

  plug Plug.Static,
    at: "/",
    from: :lanternhall,
    gzip: not code_reloading?,
    only: LanternhallWeb.static_paths(),
    raise_on_missing_only: code_reloading?,
    cache_control_for_vsn_requests: "public, max-age=31536000, immutable"

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :lanternhall

    plug Phoenix.LiveDashboard.RequestLogger,
      param_key: "request_logger",
      cookie_key: "request_logger"
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LanternhallWeb.Router
end
