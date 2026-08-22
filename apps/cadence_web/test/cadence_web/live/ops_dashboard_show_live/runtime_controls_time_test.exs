defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlsTimeTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls
  alias Phoenix.LiveView.Socket

  test "time presets clear active selection and patch a sliding live window" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: %{"target" => "telemetry_sample"},
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    socket = RuntimeControls.set_time_preset(socket, "last_5m", patch_opts())

    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "none"

    assert socket.assigns.patched_query == %{
             "time_mode" => nil,
             "time_axis" => nil,
             "from" => "now-5m",
             "to" => "now",
             "replay_run_id" => nil
           }
  end

  test "unknown time presets flash an error" do
    socket = RuntimeControls.set_time_preset(socket(), "last_5y", patch_opts())

    assert socket.assigns.flash["error"] == "Unknown dashboard time preset."
  end

  test "pause_at_selected_time patches a centered archive range" do
    socket =
      socket(%{
        dashboard_selected_data_ref: %{
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-25 12:00:00Z], :millisecond)
        }
      })

    socket = RuntimeControls.pause_at_selected_time(socket, patch_opts())

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "from" => "2026-06-25T11:57:30.000Z",
             "to" => "2026-06-25T12:02:30.000Z"
           }
  end

  test "pause_at_selected_time reports a missing timestamped selection" do
    socket = RuntimeControls.pause_at_selected_time(socket(), patch_opts())

    assert socket.assigns.flash["error"] == "Select a timestamped dashboard datum first."
  end

  test "chart range selection patches the whole dashboard into archive mode" do
    socket =
      RuntimeControls.set_chart_time_range(
        socket(%{dashboard_selected_data_ref: %{"target" => "telemetry_sample"}}),
        %{"from" => "2026-06-25T11:58:00Z", "to" => "2026-06-25T12:00:00Z"},
        patch_opts()
      )

    assert socket.assigns.dashboard_selected_data_ref == nil

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "from" => "2026-06-25T11:58:00Z",
             "to" => "2026-06-25T12:00:00Z",
             "replay_run_id" => nil
           }
  end

  test "chart range selection accepts sliding expressions and stays live" do
    socket =
      RuntimeControls.set_chart_time_range(
        socket(),
        %{"from" => " now-6h ", "to" => "now"},
        patch_opts()
      )

    assert socket.assigns.patched_query == %{
             "time_mode" => nil,
             "from" => "now-6h",
             "to" => "now",
             "replay_run_id" => nil
           }
  end

  test "chart range selection freezes relative-but-not-sliding bounds" do
    socket =
      RuntimeControls.set_chart_time_range(
        socket(),
        %{"from" => "now-6h", "to" => "now-3h"},
        Keyword.merge(patch_opts(), now: ~U[2026-06-25 12:00:00Z])
      )

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "from" => "2026-06-25T06:00:00Z",
             "to" => "2026-06-25T09:00:00Z",
             "replay_run_id" => nil
           }
  end

  test "chart range selection rejects oversized sliding windows" do
    socket =
      RuntimeControls.set_chart_time_range(
        socket(),
        %{"from" => "now-7d", "to" => "now"},
        patch_opts()
      )

    assert socket.assigns.flash["error"] =~ "capped at 24 hours"
  end

  test "shift_time_range moves an archive range by half its span" do
    socket =
      socket(%{
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T15:00:00Z",
        dashboard_time_to: "2026-06-25T19:00:00Z"
      })

    back = RuntimeControls.shift_time_range(socket, :back, patch_opts())

    assert back.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "from" => "2026-06-25T13:00:00Z",
             "to" => "2026-06-25T17:00:00Z",
             "replay_run_id" => nil
           }

    forward = RuntimeControls.shift_time_range(socket, :forward, patch_opts())

    assert forward.assigns.patched_query["from"] == "2026-06-25T17:00:00Z"
    assert forward.assigns.patched_query["to"] == "2026-06-25T21:00:00Z"
  end

  test "shift_time_range freezes a sliding window into an archive range" do
    socket =
      socket(%{
        dashboard_time_mode: "live",
        dashboard_time_from: "now-1h",
        dashboard_time_to: "now"
      })

    socket =
      RuntimeControls.shift_time_range(
        socket,
        :back,
        Keyword.merge(patch_opts(), now: ~U[2026-06-25 12:00:00Z])
      )

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "from" => "2026-06-25T10:30:00Z",
             "to" => "2026-06-25T11:30:00Z",
             "replay_run_id" => nil
           }
  end

  test "zoom_out_time_range doubles the span around its center" do
    socket =
      socket(%{
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T16:00:00Z",
        dashboard_time_to: "2026-06-25T18:00:00Z"
      })

    socket = RuntimeControls.zoom_out_time_range(socket, patch_opts())

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => "generation_time",
             "from" => "2026-06-25T15:00:00Z",
             "to" => "2026-06-25T19:00:00Z",
             "replay_run_id" => nil
           }
  end

  test "shift and zoom are no-ops without a bounded range or in replay mode" do
    plain_live = RuntimeControls.shift_time_range(socket(), :back, patch_opts())
    refute Map.has_key?(plain_live.assigns, :patched_query)

    replay =
      RuntimeControls.zoom_out_time_range(
        socket(%{
          dashboard_time_mode: "replay_run",
          dashboard_time_from: "2026-06-25T16:00:00Z",
          dashboard_time_to: "2026-06-25T18:00:00Z"
        }),
        patch_opts()
      )

    refute Map.has_key?(replay.assigns, :patched_query)
  end

  test "load_time_recents keeps only valid absolute ranges, capped at four" do
    ranges = [
      %{"from" => "2026-06-25T10:00:00Z", "to" => "2026-06-25T11:00:00Z"},
      %{"from" => "now-6h", "to" => "now"},
      %{"from" => "not-a-time", "to" => "2026-06-25T11:00:00Z"},
      %{"from" => "2026-06-25T12:00:00Z", "to" => "2026-06-25T11:00:00Z"},
      %{"from" => "2026-06-24T10:00:00Z", "to" => "2026-06-24T11:00:00Z"},
      %{"from" => "2026-06-23T10:00:00Z", "to" => "2026-06-23T11:00:00Z"},
      %{"from" => "2026-06-22T10:00:00Z", "to" => "2026-06-22T11:00:00Z"},
      %{"from" => "2026-06-21T10:00:00Z", "to" => "2026-06-21T11:00:00Z"}
    ]

    socket = RuntimeControls.load_time_recents(socket(), ranges)

    assert socket.assigns.dashboard_time_recent_ranges == [
             %{from: "2026-06-25T10:00:00Z", to: "2026-06-25T11:00:00Z"},
             %{from: "2026-06-24T10:00:00Z", to: "2026-06-24T11:00:00Z"},
             %{from: "2026-06-23T10:00:00Z", to: "2026-06-23T11:00:00Z"},
             %{from: "2026-06-22T10:00:00Z", to: "2026-06-22T11:00:00Z"}
           ]

    assert RuntimeControls.load_time_recents(socket(), "junk").assigns.dashboard_time_recent_ranges ==
             []
  end

  test "time_quick_search assigns the quick range filter" do
    socket = RuntimeControls.time_quick_search(socket(), "6 h")
    assert socket.assigns.dashboard_time_quick_query == "6 h"
  end

  defp patch_opts do
    [
      patch: fn socket, query -> assign(socket, :patched_query, query) end,
      valid_contact?: fn _scope, _mission, _contact_id -> false end
    ]
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            spacecraft: [%{spacecraft_id: "sc-1"}],
            dashboard_document: document(),
            dashboard_data_realms: ["flight"],
            dashboard_data_bindings: [data_binding()],
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_evidence_query: nil,
            context_scope_kind: nil,
            context_scope_id: nil,
            dashboard_time_mode: "live",
            dashboard_time_from: nil,
            dashboard_time_to: nil,
            dashboard_time_axis: "generation_time",
            dashboard_replay_run_id: nil,
            dashboard_data_realm: "flight",
            dashboard_data_view: "canonical",
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_limit_mode: "observed",
            dashboard_selection_state: "none",
            panel: nil
          },
          assigns
        )
    }
  end

  defp document do
    %Document{
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "flight-binding"}
          },
          "view" => "canonical"
        }
      }
    }
  end

  defp data_binding(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        binding_id: "flight-binding",
        data_source_id: "questdb-flight",
        dataset: "flight",
        realm: :flight,
        logical_source: :telemetry,
        priority: 0,
        status: :active
      })

    struct!(DataBinding, attrs)
  end
end
