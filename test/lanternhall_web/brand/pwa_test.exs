defmodule LanternhallWeb.Brand.PWATest do
  # Favicon, touch icon and web app manifest (SPEC-platform.md section 3.8).
  use LanternhallWeb.ConnCase, async: true

  @files [
    {"/images/favicon.svg", "image/svg+xml"},
    {"/images/favicon-32.png", "image/png"},
    {"/images/apple-touch-icon.png", "image/png"},
    {"/images/icon-192.png", "image/png"},
    {"/images/icon-512.png", "image/png"},
    {"/images/icon-maskable-512.png", "image/png"},
    {"/manifest.webmanifest", "application/manifest+json"}
  ]

  for {path, type} <- @files do
    describe path do
      test "is served as #{type}, revalidated by etag", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert response(conn, 200)
        assert get_resp_header(conn, "content-type") == [unquote(type)]
        assert get_resp_header(conn, "cache-control") == ["public"]
        assert [_etag] = get_resp_header(conn, "etag")
      end

      test "digested, is cached for a year, immutable", %{conn: conn} do
        conn = get(conn, unquote(path) <> "?vsn=d")

        assert response(conn, 200)
        assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      end
    end
  end

  test "the manifest makes Lanternhall a standalone app with the dark theme colors", %{
    conn: conn
  } do
    manifest = conn |> get(~p"/manifest.webmanifest") |> response(200) |> JSON.decode!()

    assert manifest == %{
             "id" => "/",
             "name" => "Lanternhall",
             "short_name" => "Lanternhall",
             "start_url" => "/",
             "scope" => "/",
             "display" => "standalone",
             "background_color" => "#121222",
             "theme_color" => "#121222",
             "icons" => [
               %{
                 "src" => "/images/icon-192.png",
                 "sizes" => "192x192",
                 "type" => "image/png",
                 "purpose" => "any"
               },
               %{
                 "src" => "/images/icon-512.png",
                 "sizes" => "512x512",
                 "type" => "image/png",
                 "purpose" => "any"
               },
               %{
                 "src" => "/images/icon-maskable-512.png",
                 "sizes" => "512x512",
                 "type" => "image/png",
                 "purpose" => "maskable"
               }
             ]
           }
  end

  test "every page links the favicons, the touch icon and the manifest", %{conn: conn} do
    head = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    links =
      for link <- head |> LazyHTML.query("head link") |> Enum.to_list(),
          rel = link |> LazyHTML.attribute("rel") |> List.first(),
          rel != "stylesheet",
          do: {rel, link |> LazyHTML.attribute("href") |> List.first()}

    assert links == [
             {"icon", "/images/favicon-32.png"},
             {"icon", "/images/favicon.svg"},
             {"apple-touch-icon", "/images/apple-touch-icon.png"},
             {"manifest", "/manifest.webmanifest"}
           ]
  end
end
