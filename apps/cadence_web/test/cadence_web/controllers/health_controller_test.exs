defmodule CadenceWeb.HealthControllerTest do
  use CadenceWeb.ConnCase, async: false

  setup do
    path = Path.join(System.tmp_dir!(), "cadence-drain-#{System.unique_integer([:positive])}")
    previous = Application.get_env(:cadence_web, :drain_file)
    Application.put_env(:cadence_web, :drain_file, path)

    on_exit(fn ->
      File.rm(path)
      Application.put_env(:cadence_web, :drain_file, previous)
    end)

    %{drain_file: path}
  end

  test "probes accept unauthenticated kubelet requests", %{conn: conn} do
    assert %{"status" => "alive"} = conn |> get("/health/live") |> json_response(200)
    assert %{"status" => "ready"} = build_conn() |> get("/health/ready") |> json_response(200)
  end

  test "the existing API health response is preserved", %{conn: conn} do
    assert %{"data" => %{"status" => "ok"}} = conn |> get("/api/health") |> json_response(200)
  end

  test "draining removes readiness without failing liveness", %{conn: conn, drain_file: path} do
    File.write!(path, "")
    assert %{"status" => "unavailable"} = conn |> get("/health/ready") |> json_response(503)
    assert %{"status" => "alive"} = build_conn() |> get("/health/live") |> json_response(200)
  end
end
