defmodule CadenceWeb.Console.Shell do
  @moduledoc """
  Produces the HTML document for the console SPA.

  The SPA owns its `index.html`; Phoenix only injects the session's CSRF token
  as `<meta name="csrf-token">` before `</head>`.

  * **Built mode** (default): reads `priv/static/console/index.html`, written
    by `vite build` in `frontend/apps/console`.
  * **Dev-server mode** (`config :cadence_web, :console, dev_server: url`):
    fetches the Vite-transformed `index.html` from the dev server and makes its
    root-relative `/console/...` script and link URLs absolute to that server,
    so Phoenix stays the page origin (same-origin cookies, CSRF, websocket)
    while modules and HMR load from Vite.
  """

  @base_path "/console/"

  @spec render(binary()) :: {:ok, binary()} | {:error, {:unavailable, binary()}}
  def render(csrf_token) when is_binary(csrf_token) do
    with {:ok, html} <- fetch_index() do
      {:ok, inject_csrf(html, csrf_token)}
    end
  end

  @doc false
  @spec inject_csrf(binary(), binary()) :: binary()
  def inject_csrf(html, csrf_token) do
    meta =
      ~s(<meta name="csrf-token" content="#{Plug.HTML.html_escape(csrf_token)}">)

    case String.split(html, "</head>", parts: 2) do
      [head, rest] -> head <> meta <> "</head>" <> rest
      [_no_head] -> meta <> html
    end
  end

  @doc false
  @spec absolutize_dev_urls(binary(), binary()) :: binary()
  def absolutize_dev_urls(html, dev_server) do
    origin = String.trim_trailing(dev_server, "/")

    Regex.replace(~r/\b(src|href)="#{@base_path}/, html, fn _match, attr ->
      ~s(#{attr}="#{origin}#{@base_path})
    end)
  end

  defp fetch_index do
    case config(:dev_server) do
      dev_server when is_binary(dev_server) -> fetch_dev_index(dev_server)
      _built -> read_built_index()
    end
  end

  defp read_built_index do
    path =
      config(:index_path) || Application.app_dir(:cadence_web, "priv/static/console/index.html")

    case File.read(path) do
      {:ok, html} ->
        {:ok, html}

      {:error, _reason} ->
        {:error,
         {:unavailable,
          "The console has not been built. Build frontend/apps/console (vite build)."}}
    end
  end

  defp fetch_dev_index(dev_server) do
    url = String.trim_trailing(dev_server, "/") <> @base_path

    case Req.get(url, receive_timeout: 5_000, retry: false, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: html}} when is_binary(html) ->
        {:ok, absolutize_dev_urls(html, dev_server)}

      _unreachable ->
        {:error,
         {:unavailable,
          "The console dev server is not reachable at #{url}. Start vite dev in frontend/apps/console."}}
    end
  end

  defp config(key) do
    :cadence_web
    |> Application.get_env(:console, [])
    |> Keyword.get(key)
  end
end
