defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{DataBinding, Document}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls
  alias Phoenix.LiveView.Socket

  test "set_runtime_context normalizes params and patches the route query" do
    socket =
      socket(%{
        dashboard_data_realms: ["flight", "rehearsal"],
        dashboard_data_bindings: [
          data_binding(),
          data_binding(%{
            binding_id: "rehearsal-fast",
            data_source_id: "questdb-rehearsal",
            realm: :rehearsal
          })
        ]
      })

    socket =
      RuntimeControls.set_runtime_context(
        socket,
        %{
          "realm" => "rehearsal",
          "data_source_id" => "questdb-rehearsal",
          "data_view" => "all_revisions",
          "ignored" => "value"
        },
        patch_opts()
      )

    assert Map.take(socket.assigns.patched_query, [
             "time_mode",
             "from",
             "to",
             "replay_run_id",
             "realm",
             "data_view",
             "data_source_id",
             "source_binding_id",
             "limit_mode"
           ]) == %{
             "time_mode" => nil,
             "from" => nil,
             "to" => nil,
             "replay_run_id" => nil,
             "realm" => "rehearsal",
             "data_view" => "all_revisions",
             "data_source_id" => "questdb-rehearsal",
             "source_binding_id" => "rehearsal-fast",
             "limit_mode" => nil
           }
  end

  test "set_context patches generic mission scope query" do
    socket =
      RuntimeControls.set_context(
        socket(),
        %{"scope_kind" => "mission", "scope_id" => "mission-1"},
        patch_opts()
      )

    assert socket.assigns.context_query == ""

    assert Map.take(socket.assigns.patched_query, [
             "spacecraft_id",
             "scope_kind",
             "scope_id"
           ]) == %{
             "spacecraft_id" => nil,
             "scope_kind" => "mission",
             "scope_id" => "mission-1"
           }
  end

  test "set_context patches durable multi-select scope query" do
    socket =
      RuntimeControls.set_context(
        socket(),
        %{
          "scope_kind" => "source_endpoint",
          "scope_ids" => ["endpoint-alpha", "endpoint-beta"]
        },
        patch_opts()
      )

    assert socket.assigns.context_query == ""

    assert Map.take(socket.assigns.patched_query, [
             "spacecraft_id",
             "scope_kind",
             "scope_id",
             "scope_ids"
           ]) == %{
             "spacecraft_id" => nil,
             "scope_kind" => "source_endpoint",
             "scope_id" => nil,
             "scope_ids" => "endpoint-alpha,endpoint-beta"
           }
  end

  test "set_context uses operational resource validation before stale selection decisions" do
    selected_ref = %{
      "target" => "telemetry_point",
      "target_id" => "HK.counter",
      "scope_kind" => "spacecraft",
      "scope_id" => "sc-1",
      "realm" => "flight"
    }

    socket =
      RuntimeControls.set_context(
        socket(%{
          dashboard_selected_data_ref: selected_ref,
          dashboard_selection_query: %{"selected_id" => "HK.counter"},
          dashboard_selection_state: "active"
        }),
        %{"scope_kind" => "transport", "scope_id" => "missing-transport"},
        Keyword.put(
          patch_opts(),
          :valid_operational_resource_scope?,
          fn _scope, _mission, scope_kind, scope_id ->
            scope_kind == "transport" and scope_id == "transport-alpha"
          end
        )
      )

    assert socket.assigns.dashboard_selected_data_ref == selected_ref
    assert socket.assigns.dashboard_selection_state == "active"
    assert socket.assigns.patched_query["scope_kind"] == "transport"
    assert socket.assigns.patched_query["scope_id"] == "missing-transport"
    assert socket.assigns.patched_query["selected_id"] == nil
  end

  test "set_context keeps spacecraft context on the legacy spacecraft query param" do
    socket = RuntimeControls.set_context(socket(), "sc-1", patch_opts())

    assert Map.take(socket.assigns.patched_query, [
             "spacecraft_id",
             "scope_kind",
             "scope_id",
             "scope_ids"
           ]) == %{
             "spacecraft_id" => "sc-1",
             "scope_kind" => nil,
             "scope_id" => nil,
             "scope_ids" => nil
           }
  end

  test "time presets clear active selection and patch an archive window" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: %{"target" => "telemetry_sample"},
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    socket =
      RuntimeControls.set_time_preset(
        socket,
        "last_5m",
        Keyword.merge(patch_opts(), now: ~U[2026-06-25 12:00:00Z])
      )

    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "none"

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => nil,
             "from" => "2026-06-25T11:55:00Z",
             "to" => "2026-06-25T12:00:00Z",
             "replay_run_id" => nil
           }
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

  test "scrub_replay_to_selection patches a centered replay range" do
    socket =
      socket(%{
        dashboard_replay_run_id: "replay-run-1",
        dashboard_selected_data_ref: %{
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-25 12:00:00Z], :millisecond)
        }
      })

    socket = RuntimeControls.scrub_replay_to_selection(socket, patch_opts())

    assert socket.assigns.patched_query == %{
             "time_mode" => "replay_run",
             "replay_run_id" => "replay-run-1",
             "from" => "2026-06-25T11:57:30.000Z",
             "to" => "2026-06-25T12:02:30.000Z"
           }
  end

  test "scrub_replay_to_selection can recover replay run id from selected data" do
    socket =
      socket(%{
        dashboard_replay_run_id: nil,
        dashboard_selected_data_ref: %{
          "replay_run_id" => "selected-replay-run",
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-25 12:00:00Z], :millisecond)
        }
      })

    socket = RuntimeControls.scrub_replay_to_selection(socket, patch_opts())

    assert socket.assigns.patched_query["replay_run_id"] == "selected-replay-run"
    assert socket.assigns.patched_query["time_mode"] == "replay_run"
  end

  test "scrub_replay_to_selection reports missing replay run before timestamp" do
    socket =
      socket(%{
        dashboard_selected_data_ref: %{
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-25 12:00:00Z], :millisecond)
        }
      })

    socket = RuntimeControls.scrub_replay_to_selection(socket, patch_opts())

    assert socket.assigns.flash["error"] == "Select a replay run before scrubbing replay time."
  end

  test "scrub_replay_to_selection reports a missing timestamped replay selection" do
    socket =
      socket(%{
        dashboard_replay_run_id: "replay-run-1",
        dashboard_selected_data_ref: %{"target" => "telemetry_sample"}
      })

    socket = RuntimeControls.scrub_replay_to_selection(socket, patch_opts())

    assert socket.assigns.flash["error"] == "Select a timestamped replay datum first."
  end

  test "clear_data_selection closes data-link panels and clears route selection query" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: %{"target" => "telemetry_sample"},
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    socket = RuntimeControls.clear_data_selection(socket, patch_opts())

    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "none"

    assert socket.assigns.patched_query == %{
             "panel" => nil,
             "selected_target" => nil,
             "selected_link" => nil,
             "selected_id" => nil,
             "selected_time" => nil,
             "selected_placement" => nil,
             "selected_data_view" => nil,
             "selected_series_role" => nil,
             "selected_compare_of" => nil,
             "selected_comparison_state" => nil,
             "selected_comparison_delta" => nil,
             "selected_primary_sample" => nil,
             "selected_compare_sample" => nil,
             "selected_primary_data_view" => nil,
             "selected_compare_data_view" => nil,
             "selected_primary_data_management" => nil,
             "selected_compare_data_management" => nil,
             "selected_primary_count" => nil,
             "selected_compare_count" => nil,
             "selected_widget" => nil,
             "selected_widget_title" => nil,
             "selected_widget_type" => nil,
             "selected_widget_source" => nil,
             "selected_primary_kind" => nil,
             "selected_compare_kind" => nil,
             "selected_primary_observables" => nil,
             "selected_compare_observables" => nil,
             "selected_scope_kind" => nil,
             "selected_scope_id" => nil,
             "selected_scope_ids" => nil,
             "selected_resource_id" => nil,
             "selected_spacecraft_id" => nil,
             "selected_contact_id" => nil,
             "selected_transport_id" => nil,
             "selected_source_endpoint_id" => nil,
             "selected_ground_station_id" => nil,
             "selected_scope_link_id" => nil,
             "nav_from_link_id" => nil,
             "nav_from_target" => nil,
             "nav_from_target_id" => nil,
             "nav_from_label" => nil,
             "nav_from_relationship_kind" => nil,
             "nav_from_relationship_label" => nil,
             "nav_trail" => nil,
             "time_axis" => nil
           }
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
