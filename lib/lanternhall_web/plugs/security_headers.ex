defmodule LanternhallWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Sets the security and cache headers on every response (SPEC-platform.md sections 3.3 and 3.8).

  It runs first in the endpoint, so HTML, static files and `/healthz` all carry:

    * a strict `Content-Security-Policy` whose only inline allowance is a per-request
      nonce, kept in `conn.assigns.csp_nonce` for the inline theme script in the root layout;
    * `X-Content-Type-Options`, `Referrer-Policy`, `Cross-Origin-Resource-Policy` and
      `Permissions-Policy`;
    * `Cache-Control: no-store`, which `Plug.Static` replaces for files it serves.

  The endpoint passes `dev_tools: true` in dev only, where the live-reload iframe,
  the error pages and LiveDashboard need inline code that cannot carry the nonce:
  pages also allow a same-origin frame, and those dev tool responses get no CSP.
  """
  @behaviour Plug

  import Plug.Conn

  @headers [
    {"x-content-type-options", "nosniff"},
    {"referrer-policy", "no-referrer"},
    {"cross-origin-resource-policy", "same-origin"},
    {"permissions-policy", "camera=(), microphone=(), geolocation=()"},
    {"cache-control", "no-store"}
  ]

  @impl Plug
  def init(opts), do: Keyword.validate!(opts, dev_tools: false)

  @impl Plug
  def call(conn, opts) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> merge_resp_headers(@headers)
    |> put_csp(nonce, opts[:dev_tools])
  end

  defp put_csp(conn, nonce, false),
    do: put_resp_header(conn, "content-security-policy", policy(nonce))

  # The live-reload frame and LiveDashboard exist in dev only.
  defp put_csp(%{path_info: ["phoenix", "live_reload", "frame" | _]} = conn, _, true), do: conn
  defp put_csp(%{path_info: ["dev" | _]} = conn, _nonce, true), do: conn

  defp put_csp(conn, nonce, true) do
    conn
    |> put_resp_header("content-security-policy", policy(nonce) <> "; frame-src 'self'")
    |> register_before_send(fn
      # Plug.Debugger and Phoenix.CodeReloader error pages use inline code.
      %{status: status} = conn when status >= 400 ->
        delete_resp_header(conn, "content-security-policy")

      conn ->
        conn
    end)
  end

  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'none'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self'",
        "img-src 'self' data:",
        "font-src 'self'",
        "connect-src 'self'",
        "manifest-src 'self'",
        "base-uri 'none'",
        "form-action 'self'",
        "frame-ancestors 'none'"
      ],
      "; "
    )
  end
end
