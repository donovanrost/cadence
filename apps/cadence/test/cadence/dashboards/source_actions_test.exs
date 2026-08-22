defmodule Cadence.Dashboards.SourceActionsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{DashboardAction, SourceActions}

  test "builds route-free source warning actions from source context" do
    actions =
      SourceActions.source_warning_actions(%{
        source_request_id: "req-telemetry",
        logical_source: :telemetry,
        binding_id: "binding-flight",
        data_source_id: "flight-questdb",
        realm: :flight,
        scope_kind: :spacecraft,
        scope_id: "spacecraft-1",
        contact_id: "contact-1",
        source_endpoint_ids: ["endpoint-1"],
        source_empty_reason: :contact_scope_no_data
      })

    assert [
             %DashboardAction{
               action_id: "dashboard-source-health-action",
               label: "Inspect source health",
               target: :source_health,
               kind: :invoke,
               route: nil,
               query: %{
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "scope_kind" => "spacecraft",
                 "scope_id" => "spacecraft-1",
                 "contact_id" => "contact-1",
                 "source_endpoint_id" => "endpoint-1",
                 "source_empty_reason" => "contact_scope_no_data"
               },
               context: %{
                 source_request_id: "req-telemetry",
                 logical_source: :telemetry,
                 source_binding_id: "binding-flight",
                 data_source_id: "flight-questdb",
                 realm: :flight,
                 scope_kind: :spacecraft,
                 scope_id: "spacecraft-1",
                 contact_id: "contact-1",
                 source_endpoint_id: "endpoint-1",
                 source_empty_reason: :contact_scope_no_data
               },
               source: :warning
             },
             %DashboardAction{
               action_id: "dashboard-source-inventory-action",
               label: "Source inventory",
               target: :source_inventory,
               kind: :invoke,
               route: nil,
               query: %{
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "scope_kind" => "spacecraft",
                 "scope_id" => "spacecraft-1",
                 "contact_id" => "contact-1",
                 "source_endpoint_id" => "endpoint-1",
                 "source_empty_reason" => "contact_scope_no_data"
               },
               context: %{
                 source_request_id: "req-telemetry",
                 logical_source: :telemetry,
                 source_binding_id: "binding-flight",
                 data_source_id: "flight-questdb",
                 realm: :flight,
                 scope_kind: :spacecraft,
                 scope_id: "spacecraft-1",
                 contact_id: "contact-1",
                 source_endpoint_id: "endpoint-1",
                 source_empty_reason: :contact_scope_no_data
               },
               source: :warning
             }
           ] = actions
  end

  test "does not add source actions without source focus context" do
    assert SourceActions.source_warning_actions(%{reason: :timeout}) == []
    assert SourceActions.put_source_warning_actions(%{reason: :timeout}) == %{reason: :timeout}
  end

  test "preserves existing warning actions when adding source actions" do
    telemetry_action = %DashboardAction{
      action_id: "telemetry-warning-explore:req-telemetry:HK.counter",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{"point_id" => "HK.counter"},
      source: :warning
    }

    details =
      SourceActions.put_source_warning_actions(%{
        source_request_id: "req-telemetry",
        logical_source: :telemetry,
        data_source_id: "flight-questdb",
        actions: [telemetry_action]
      })

    assert [
             %DashboardAction{target: :telemetry_explore},
             %DashboardAction{target: :source_health},
             %DashboardAction{target: :source_inventory}
           ] = details.actions
  end

  test "builds route-free publish readiness actions for every source warning code" do
    expected_targets = %{
      missing_source_binding: :source_inventory,
      missing_data_source: :source_inventory,
      disabled_data_source: :source_inventory,
      unsupported_source_capability: :source_inventory,
      source_unavailable: :source_health,
      source_connection_failed: :source_health,
      source_degraded: :source_health,
      missing_replay_run_id: :source_inventory,
      missing_replay_source_binding: :source_inventory,
      replay_source_required: :source_inventory,
      invalid_data_source_configuration: :source_inventory,
      source_binding_interval_ambiguous: :source_inventory,
      unsupported_observable_scope: :dashboard_editor
    }

    for {warning_code, expected_target} <- expected_targets do
      assert %DashboardAction{
               action_id: "dashboard-publish-source-readiness-action",
               label: label,
               message: message,
               target: ^expected_target,
               kind: :invoke,
               route: nil,
               source: :warning,
               query: query,
               context: context
             } =
               SourceActions.publish_readiness_action(%{
                 source_warning_code: warning_code,
                 placement_id: "placement-source-readiness",
                 details: publish_readiness_source_details()
               })

      assert is_binary(label) and label != ""
      assert is_binary(message) and message != ""

      assert context.logical_source == :telemetry
      assert context.source_binding_id == "flight-binding"
      assert context.data_source_id == "flight-tsdb"
      assert context.realm == :flight
      assert context.placement_id == "placement-source-readiness"
      assert context.source_empty_reason == expected_source_empty_reason(warning_code)

      assert query["logical_source"] == "telemetry"
      assert query["source_binding_id"] == "flight-binding"
      assert query["data_source_id"] == "flight-tsdb"
      assert query["realm"] == "flight"
      assert query["placement_id"] == "placement-source-readiness"
      assert query["source_empty_reason"] == stringify_source_empty_reason(warning_code)
    end
  end

  test "builds publish readiness action for source capability blockers" do
    assert %DashboardAction{
             action_id: "dashboard-publish-source-readiness-action",
             label: "Use a compatible source",
             message:
               "Open Data Sources and choose a source whose capabilities support the widget request, or change the widget sampling requirements.",
             target: :source_inventory,
             kind: :invoke,
             query: %{
               "data_source_id" => "rehearsal-source",
               "source_binding_id" => "rehearsal-binding",
               "logical_source" => "telemetry",
               "realm" => "rehearsal",
               "source_empty_reason" => "unsupported_source_capability",
               "requested_sampling" => "bounded_history",
               "supported_sampling" => "latest",
               "requested_products" => "bounded_receipt_time_history",
               "supported_products" => "latest_value",
               "requested_value_kinds" => "engineering",
               "supported_value_kinds" => "raw"
             },
             context: %{
               data_source_id: "rehearsal-source",
               source_binding_id: "rehearsal-binding",
               logical_source: :telemetry,
               realm: :rehearsal,
               source_empty_reason: :unsupported_source_capability,
               requested_sampling: :bounded_history,
               supported_sampling: :latest,
               requested_products: :bounded_receipt_time_history,
               supported_products: :latest_value,
               requested_value_kinds: :engineering,
               supported_value_kinds: :raw
             },
             source: :warning
           } =
             SourceActions.publish_readiness_action(%{
               source_warning_code: :unsupported_source_capability,
               details: %{
                 logical_source: :telemetry,
                 realm: :rehearsal,
                 source_binding_id: "rehearsal-binding",
                 data_source_id: "rehearsal-source",
                 requested_sampling: :bounded_history,
                 supported_sampling: [:latest],
                 requested_products: [:bounded_receipt_time_history],
                 supported_products: [:latest_value],
                 requested_value_kinds: [:engineering],
                 supported_value_kinds: [:raw]
               }
             })
  end

  test "builds dashboard editor action for operational source capability blockers" do
    assert %DashboardAction{
             label: "Review operational history binding",
             target: :dashboard_editor,
             query: %{
               "placement_id" => "placement-link-history",
               "logical_source" => "operational_observables",
               "source_empty_reason" => "unsupported_source_capability",
               "requested_observables" => "link.snr_db",
               "unsupported_observables" => "link.snr_db",
               "requested_sampling" => "raw_series",
               "requested_products" => "link_rf",
               "requested_source_products" => "link_rf_metric_history",
               "requested_product_families" => "link_rf",
               "supported_sampling" => "latest, event_history"
             },
             context: %{
               placement_id: "placement-link-history",
               logical_source: :operational_observables,
               source_empty_reason: :unsupported_source_capability,
               requested_observables: "link.snr_db",
               unsupported_observables: "link.snr_db",
               requested_sampling: :raw_series,
               requested_products: :link_rf,
               requested_source_products: :link_rf_metric_history,
               requested_product_families: :link_rf,
               supported_sampling: "latest, event_history"
             }
           } =
             SourceActions.publish_readiness_action(%{
               source_warning_code: :unsupported_source_capability,
               placement_id: "placement-link-history",
               details: %{
                 logical_source: :operational_observables,
                 requested_observables: ["link.snr_db"],
                 unsupported_observables: ["link.snr_db"],
                 requested_sampling: :raw_series,
                 requested_products: [:link_rf],
                 requested_source_products: [:link_rf_metric_history],
                 requested_product_families: [:link_rf],
                 supported_sampling: [:latest, :event_history]
               }
             })
  end

  test "builds publish readiness action for failed connection tests" do
    assert %DashboardAction{
             label: "Fix source connection",
             target: :source_health,
             query: %{
               "data_source_id" => "rehearsal-source",
               "source_binding_id" => "rehearsal-binding",
               "source_empty_reason" => "connection_test_failed",
               "selected_evidence_kind" => "source",
               "selected_source_evidence_mode" => "health",
               "selected_source_evidence_state" => "connection_test_failed",
               "connection_test_result" => "failed",
               "connection_test_kind" => "adapter_io",
               "connection_test_message" => "Adapter connection test failed."
             }
           } =
             SourceActions.publish_readiness_action(%{
               source_warning_code: :source_connection_failed,
               details: %{
                 binding_id: "rehearsal-binding",
                 data_source_id: "rehearsal-source",
                 connection_test_result: "failed",
                 connection_test_kind: "adapter_io",
                 connection_test_message: "Adapter connection test failed."
               }
             })
  end

  test "builds publish readiness action for dashboard context blockers" do
    assert %DashboardAction{
             label: "Change widget context",
             target: :dashboard_editor,
             query: %{
               "placement_id" => "tile-ground-state",
               "logical_source" => "operational_observables",
               "scope_kind" => "spacecraft",
               "source_empty_reason" => "unsupported_observable_scope",
               "unsupported_observables" => "ground.station.connection_state"
             }
           } =
             SourceActions.publish_readiness_action(%{
               source_warning_code: :unsupported_observable_scope,
               placement_id: "tile-ground-state",
               details: %{
                 logical_source: :operational_observables,
                 requested_scope_kind: :spacecraft,
                 requested_scope_ids: [],
                 unsupported_observables: ["ground.station.connection_state"]
               }
             })
  end

  defp publish_readiness_source_details do
    %{
      logical_source: :telemetry,
      realm: :flight,
      source_binding_id: "flight-binding",
      data_source_id: "flight-tsdb",
      requested_sampling: [:bounded_history],
      supported_sampling: [:latest],
      requested_products: [:bounded_receipt_time_history],
      supported_products: [:latest_value],
      requested_value_kinds: [:engineering],
      supported_value_kinds: [:raw],
      requested_scope_kind: :source_endpoint,
      requested_scope_ids: ["source-endpoint-1"],
      unsupported_observables: ["ground.station.connection_state"],
      connection_test_result: "failed",
      connection_test_kind: "adapter_io",
      connection_test_message: "Adapter connection test failed."
    }
  end

  defp expected_source_empty_reason(:source_connection_failed), do: "connection_test_failed"
  defp expected_source_empty_reason(warning_code), do: warning_code

  defp stringify_source_empty_reason(:source_connection_failed), do: "connection_test_failed"
  defp stringify_source_empty_reason(warning_code), do: Atom.to_string(warning_code)
end
