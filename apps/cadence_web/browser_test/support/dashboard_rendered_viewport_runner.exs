defmodule CadenceWeb.Assets.DashboardRenderedViewportRunner do
  @moduledoc false

  @dashboard_viewport_smoke_timeout_ms 540_000
  @dashboard_viewport_smoke_shutdown_timeout_ms 5_000

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Ecto.Adapters.SQL.Sandbox

  def ensure_assets_built!(app_root) do
    assert {output, 0} =
             System.cmd("mix", ["assets.build"],
               cd: app_root,
               env: [{"MIX_ENV", "test"}],
               stderr_to_stdout: true
             )

    assert output =~ "tailwindcss"
    assert File.exists?(Path.join(app_root, "priv/static/assets/app.css"))
    assert File.exists?(Path.join(app_root, "priv/static/assets/app.js"))
  end

  def free_tcp_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  def run_dashboard_viewport_smoke(args, opts) when is_list(args) do
    node = System.find_executable("node") || raise "node executable is required"
    timeout = Keyword.get(opts, :timeout, @dashboard_viewport_smoke_timeout_ms)

    port_opts =
      [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args}
      ]
      |> maybe_put_port_cd(Keyword.get(opts, :cd))
      |> maybe_put_port_env(Keyword.get(opts, :env))

    port = Port.open({:spawn_executable, node}, port_opts)
    deadline = System.monotonic_time(:millisecond) + timeout

    collect_dashboard_viewport_smoke(port, "", deadline, timeout)
  end

  def maybe_put_port_cd(port_opts, cd) when is_binary(cd), do: [{:cd, cd} | port_opts]
  def maybe_put_port_cd(port_opts, _cd), do: port_opts

  def maybe_put_port_env(port_opts, env) when is_list(env), do: [{:env, env} | port_opts]
  def maybe_put_port_env(port_opts, _env), do: port_opts

  def collect_dashboard_viewport_smoke(port, output, deadline, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_dashboard_viewport_smoke(port, output <> data, deadline, timeout)

      {^port, {:exit_status, status}} ->
        {output, status}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        timeout_output =
          output <>
            "\nDashboard viewport smoke timed out after #{timeout}ms; terminating node process.\n"

        terminate_dashboard_viewport_smoke(port, timeout_output)
    end
  end

  def terminate_dashboard_viewport_smoke(port, output) do
    kill_dashboard_viewport_smoke(port, "TERM")

    receive do
      {^port, {:data, data}} ->
        terminate_dashboard_viewport_smoke(port, output <> data)

      {^port, {:exit_status, status}} ->
        {output, status}
    after
      @dashboard_viewport_smoke_shutdown_timeout_ms ->
        kill_dashboard_viewport_smoke(port, "KILL")

        receive do
          {^port, {:data, data}} -> {output <> data, 124}
          {^port, {:exit_status, status}} -> {output, status}
        after
          1_000 -> {output, 124}
        end
    end
  end

  def kill_dashboard_viewport_smoke(port, signal) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) ->
        System.cmd("kill", ["-#{signal}", Integer.to_string(os_pid)], stderr_to_stdout: true)

      _ ->
        :ok
    end
  end

  def start_browser_endpoint!(port, sandbox_owner) do
    endpoint_id = {:dashboard_browser_endpoint, port}

    :ok = Sandbox.mode(Cadence.Repo, {:shared, sandbox_owner})

    endpoint_pid =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit, plug: CadenceWeb.Endpoint, scheme: :http, ip: {127, 0, 0, 1}, port: port},
          id: endpoint_id,
          restart: :temporary
        )
      )

    on_exit(fn ->
      stop_browser_endpoint(endpoint_pid)
      Process.sleep(50)
    end)

    endpoint_pid
  end

  def stop_browser_endpoint(pid) when is_pid(pid) do
    ref = Process.monitor(pid)

    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      1_000 -> Process.demonitor(ref, [:flush])
    end
  end

  def rendered_dashboard_artifact!(html, app_root) do
    path =
      Path.join(System.tmp_dir!(), "cadence-rendered-dashboard-#{System.unique_integer()}.html")

    File.write!(path, rendered_dashboard_document(html, app_root))
    path
  end

  def rendered_dashboard_document(html, app_root) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Rendered dashboard viewport smoke</title>
        <link rel="stylesheet" href="#{asset_file_url(app_root, "app.css")}" />
        <style>
          #{rendered_dashboard_smoke_css()}
        </style>
      </head>
      <body>
        #{html}
      </body>
    </html>
    """
  end

  def asset_file_url(app_root, filename) do
    app_root
    |> Path.join("priv/static/assets/#{filename}")
    |> Path.expand()
    |> then(&"file://#{&1}")
  end

  def rendered_dashboard_smoke_css do
    """
    :root {
      color-scheme: dark;
      --bg: #10131d;
      --panel: #171b28;
      --panel-strong: #202638;
      --line: rgba(114, 211, 255, 0.28);
      --line-strong: rgba(114, 211, 255, 0.52);
      --text: #d9e4f1;
      --muted: #8c9bb2;
      --accent: #f04f9c;
      --cell: 88px;
    }

    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--text); }
    body { font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    button, a { color: inherit; font: inherit; }
    .hidden { display: none !important; }

    #ops-dashboard-show-page {
      min-height: 900px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      padding: 12px 392px 12px 12px;
      overflow: hidden;
    }

    #ops-dashboard-show-page > div:first-child {
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 38px;
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      padding: 6px 8px;
    }

    #ops-dashboard-show-page h1,
    #ops-dashboard-show-page h2,
    #dashboard-panel h2 {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
      font-size: 0.95rem;
      line-height: 1.2;
    }

    #ops-dashboard-show-page button,
    #ops-dashboard-show-page a,
    #dashboard-panel button {
      max-width: 100%;
      overflow-wrap: anywhere;
    }

    #dashboard-menu {
      flex: 0 0 auto;
    }

    .grid-stack {
      position: relative;
      min-height: 540px;
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 6px;
    }

    .grid-stack > .grid-stack-item {
      position: absolute;
      padding: 0;
      min-height: 80px;
    }

    .grid-stack > .grid-stack-item[gs-y="0"] { top: 0; }
    .grid-stack > .grid-stack-item[gs-y="1"] { top: calc(var(--cell) * 1); }
    .grid-stack > .grid-stack-item[gs-y="2"] { top: calc(var(--cell) * 2); }
    .grid-stack > .grid-stack-item[gs-y="3"] { top: calc(var(--cell) * 3); }
    .grid-stack > .grid-stack-item[gs-x="0"] { left: 0; }
    .grid-stack > .grid-stack-item[gs-x="4"] { left: 33.333%; }
    .grid-stack > .grid-stack-item[gs-w="4"] { width: 33.333%; }
    .grid-stack > .grid-stack-item[gs-w="6"] { width: 50%; }
    .grid-stack > .grid-stack-item[gs-h="2"] { height: calc(var(--cell) * 2); }
    .grid-stack > .grid-stack-item[gs-h="3"] { height: calc(var(--cell) * 3); }

    .grid-stack-item-content {
      position: absolute;
      inset: 0;
      display: flex;
      min-width: 0;
      min-height: 0;
      flex-direction: column;
      gap: 8px;
      overflow: hidden;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      padding: 10px;
    }

    [phx-hook="TelemetryChart"] {
      display: block;
      flex: 1 1 auto;
      min-height: 132px;
      width: 100%;
      border: 1px solid var(--line-strong);
      border-radius: 4px;
      background:
        linear-gradient(to right, rgba(114, 211, 255, 0.14) 1px, transparent 1px) 0 0 / 48px 100%,
        linear-gradient(to bottom, rgba(114, 211, 255, 0.10) 1px, transparent 1px) 0 0 / 100% 36px,
        #111827;
    }

    #dashboard-panel {
      position: fixed;
      top: 0;
      right: 0;
      bottom: 0;
      z-index: 2;
      width: 360px;
      max-width: calc(100vw - 24px);
      display: flex;
      flex-direction: column;
      gap: 10px;
      overflow: auto;
      border-left: 1px solid var(--line-strong);
      background: var(--panel);
      padding: 12px;
    }

    #dashboard-data-link-inspector,
    #dashboard-evidence-inspector {
      display: grid;
      gap: 10px;
      min-width: 0;
    }

    #dashboard-panel dl {
      display: grid;
      grid-template-columns: minmax(84px, 7rem) minmax(0, 1fr);
      gap: 4px 8px;
    }

    #dashboard-panel dd,
    #dashboard-panel dt {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
    }

    @media (max-width: 720px) {
      #ops-dashboard-show-page {
        min-height: 0;
        padding: 12px;
      }

      #ops-dashboard-show-page > div:first-child {
        align-items: stretch;
        flex-direction: column;
      }

      .grid-stack {
        min-height: 0;
        border: 0;
      }

      .grid-stack > .grid-stack-item {
        position: relative;
        top: auto !important;
        left: auto !important;
        width: 100% !important;
        height: auto !important;
        margin-bottom: 12px;
      }

      .grid-stack-item-content {
        position: relative;
        min-height: 140px;
      }

      .grid-stack > .grid-stack-item > .grid-stack-item-content {
        position: relative;
        min-height: 140px;
      }

      #dashboard-panel {
        position: relative;
        width: auto;
        max-width: none;
        margin-top: 12px;
      }
    }
    """
  end
end
