defmodule CadenceWeb.OpsWorkspaceURLTest do
  use ExUnit.Case, async: true
  alias CadenceWeb.OpsWorkspaceURL

  test "absent context preserves document defaults; only finite scalar enums are admitted" do
    assert {:ok, %{time_context: %{}, data_context: %{}, limit_context: %{}}} =
             OpsWorkspaceURL.admit(%{"mission_id" => "m", "dashboard_id" => "d"})

    assert {:ok, runtime} =
             OpsWorkspaceURL.admit(%{
               "time_mode" => "live",
               "time_axis" => "receipt_time",
               "realm" => "rehearsal",
               "selection_view" => "as_recorded",
               "limit_mode" => "compare"
             })

    assert runtime.time_context == %{mode: "live", axis: "receipt_time"}
    assert runtime.data_context == %{realm: "rehearsal", view: "as_recorded"}
    assert runtime.limit_context == %{semantics_mode: "compare"}
  end

  test "range and archive require timezone-qualified increasing bounded endpoints" do
    for mode <- ~w(range archive) do
      params = %{
        "time_mode" => mode,
        "from" => "2026-09-07T01:00:00+01:00",
        "to" => "2026-09-07T01:00:00Z"
      }

      assert {:ok, %{time_context: %{from: from, to: to}}} = OpsWorkspaceURL.admit(params)
      assert from == ~U[2026-09-07 00:00:00Z]
      assert to == ~U[2026-09-07 01:00:00Z]

      for invalid <- [
            Map.delete(params, "from"),
            Map.put(params, "from", params["to"]),
            Map.put(params, "from", "2026-09-08T00:00:00Z"),
            Map.put(params, "from", "2026-01-01T00:00:00Z"),
            Map.put(params, "from", "2026-09-07T00:00:00"),
            Map.put(params, "from", %{"nested" => "invalid"}),
            Map.put(params, "time_mode", "live")
          ] do
        assert {:error, :invalid_context} = OpsWorkspaceURL.admit(invalid)
      end
    end
  end

  test "unsupported context and malformed input fail instead of silently changing its meaning" do
    for params <- [
          nil,
          %{"time_mode" => ""},
          %{"time_mode" => ["live"]},
          %{"time_mode" => "replay_run", "replay_run_id" => "r"},
          %{"time_axis" => "occurred_at"},
          %{"realm" => "secret"},
          %{"selection_view" => "other"},
          %{"limit_mode" => "other"},
          %{"source_binding_id" => "b"},
          %{"data_source_id" => "d"},
          %{"selected_scope_id" => "other"},
          %{"selected_widget" => "w"},
          %{"runtime" => %{}},
          %{"organization_id" => "forged"},
          %{"from" => "2026-09-07T00:00:00Z"}
        ] do
      assert {:error, :invalid_context} = OpsWorkspaceURL.admit(params)
    end
  end

  test "Grafana relative bounds become a live sliding window; frozen relative ranges are refused" do
    assert {:ok, %{time_context: %{mode: "live", window_seconds: 21_600}}} =
             OpsWorkspaceURL.admit(%{"from" => "now-6h", "to" => "now"})

    assert {:ok, %{time_context: %{mode: "range", from: ~U[2026-09-07 00:00:00Z]}}} =
             OpsWorkspaceURL.admit(%{
               "from" => "2026-09-07T00:00:00Z",
               "to" => "2026-09-07T01:00:00Z"
             })

    for invalid <- [
          %{"from" => "now-6h", "to" => "now-1h"},
          %{"from" => "now-30d", "to" => "now"},
          %{"from" => "now-6h", "to" => "now", "time_mode" => "archive"},
          %{"from" => "now-6h"}
        ] do
      assert {:error, :invalid_context} = OpsWorkspaceURL.admit(invalid)
    end
  end

  test "a spacecraft scope is admitted as one bounded id for the page to check" do
    assert {:ok, runtime} = OpsWorkspaceURL.admit(%{"spacecraft" => "sc-1"})

    assert runtime.scope_context == %{
             primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]},
             spacecraft_id: "sc-1"
           }

    assert OpsWorkspaceURL.spacecraft(runtime) == "sc-1"

    for invalid <- ["", String.duplicate("x", 257), <<0xFF>>, ["sc-1"]] do
      assert {:error, :invalid_context} = OpsWorkspaceURL.admit(%{"spacecraft" => invalid})
    end
  end
end
