defmodule LanternhallWeb.Plugs.SecurityHeaders do
  @moduledoc false
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

  defp put_csp(conn, nonce, false), do: put_csp(conn, policy(nonce))

  defp put_csp(%{path_info: ["phoenix", "live_reload", "frame" | _]} = conn, _nonce, true),
    do: put_csp(conn, "frame-ancestors 'self'")

  defp put_csp(%{path_info: ["dev" | _]} = conn, _nonce, true),
    do: put_csp(conn, "frame-ancestors 'none'")

  defp put_csp(conn, nonce, true) do
    conn
    |> put_csp(policy(nonce) <> "; frame-src 'self'")
    |> register_before_send(fn
      # Plug.Debugger and Phoenix.CodeReloader error pages use inline code.
      %{status: status} = conn when status >= 400 -> put_csp(conn, "frame-ancestors 'none'")
      conn -> conn
    end)
  end

  defp put_csp(conn, policy), do: put_resp_header(conn, "content-security-policy", policy)

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
