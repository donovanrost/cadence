defmodule CadenceWeb.HealthControllerTest do
  use CadenceWeb.ConnCase, async: false
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "drain")
    previous = Application.get_env(:cadence_web, :drain_file)
    Application.put_env(:cadence_web, :drain_file, path)

    on_exit(fn ->
      Application.put_env(:cadence_web, :drain_file, previous)
    end)

    %{drain_file: path}
  end

  test "probes accept unauthenticated kubelet requests", %{conn: conn} do
    assert %{"status" => "alive"} = conn |> get("/health/live") |> json_response(200)
    assert %{"status" => "ready"} = build_conn() |> get("/health/ready") |> json_response(200)
  end

  test "draining removes readiness without failing liveness", %{conn: conn, drain_file: path} do
    File.write!(path, "")
    assert %{"status" => "unavailable"} = conn |> get("/health/ready") |> json_response(503)
    assert %{"status" => "alive"} = build_conn() |> get("/health/live") |> json_response(200)
  end

  test "process drain removes readiness without a deployment-specific marker", %{conn: conn} do
    key = {Cadence.Platform.Drain, Cadence.Platform.Drain}
    :persistent_term.put(key, true)
    on_exit(fn -> :persistent_term.erase(key) end)
    assert %{"status" => "unavailable"} = conn |> get("/health/ready") |> json_response(503)
    assert %{"status" => "alive"} = build_conn() |> get("/health/live") |> json_response(200)
  end
end
