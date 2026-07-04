defmodule CadenceWeb.OpsDashboardShowLive.PublishValidationPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.ValidationResult
  alias CadenceWeb.OpsDashboardShowLive.PublishValidationPresentation

  test "build returns nil when no validation result is present" do
    assert PublishValidationPresentation.build(nil) == nil
  end

  test "build presents clean publish validation" do
    assert PublishValidationPresentation.build(%ValidationResult{}) == %{
             status: "clean",
             label: "ready",
             message: "This draft is ready to publish.",
             badge_class: "badge-success",
             result: %{
               state: "resolved",
               label: "resolved",
               message: "Latest check found no publish blockers."
             },
             issues: []
           }
  end

  test "build presents stale publish validation when freshness is stale" do
    validation = %ValidationResult{
      valid?: false,
      errors: [%{code: :invalid_grid, details: %{field: :columns}}]
    }

    assert %{
             status: "stale",
             label: "needs re-check",
             message:
               "Draft changed after this publish check. Re-check readiness before publishing.",
             badge_class: "badge-warning",
             result: %{
               state: "needs_recheck",
               label: "needs re-check",
               message:
                 "This publish check is stale. Re-check readiness against the current draft."
             },
             issues: [%{severity: :error, code: "invalid_grid"}]
           } = PublishValidationPresentation.build(validation, %{state: "stale"})
  end

  test "build presents source evidence stale publish validation reason" do
    validation = %ValidationResult{
      warnings: [%{code: :stale_data, details: %{data_source_id: "source-1"}}]
    }

    assert %{
             status: "stale",
             label: "needs re-check",
             message:
               "Source watermark evidence is stale; re-check readiness after source data advances. Re-check readiness before publishing.",
             result: %{
               state: "needs_recheck",
               message:
                 "Source watermark evidence is stale; re-check readiness after source data advances."
             },
             issues: [%{severity: :warning, code: "stale_data"}]
           } =
             PublishValidationPresentation.build(validation, %{
               state: "stale",
               reason: "source_watermark_stale",
               message:
                 "Source watermark evidence is stale; re-check readiness after source data advances."
             })
  end

  test "build presents warning publish validation" do
    validation = %ValidationResult{
      warnings: [
        %{
          code: :unknown_widget_type,
          details: %{widget_type_id: "legacy.widget"}
        }
      ]
    }

    assert %{
             status: "warnings",
             label: "warnings",
             message: "This draft can publish, but retained content has warnings.",
             badge_class: "badge-warning",
             result: %{
               state: "resolved_with_warnings",
               label: "resolved with warnings",
               message: "Latest check found no publish blockers, but warnings remain."
             },
             issues: [
               %{
                 severity: :warning,
                 severity_text: "warning",
                 badge_class: "badge-warning",
                 code: "unknown_widget_type",
                 message: "Review the validation details below.",
                 action: nil,
                 detail_rows: [%{label: "Widget type", value: "legacy.widget"}]
               }
             ]
           } = PublishValidationPresentation.build(validation)
  end

  test "build presents blocked publish validation with error issues before warnings" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{code: "invalid_grid", details: %{field: :columns}}
      ],
      warnings: [
        %{code: :unknown_widget_type, details: %{widget_type_id: "legacy.widget"}}
      ]
    }

    assert %{
             status: "blocked",
             label: "blocked",
             message: "Resolve validation errors before publishing this draft.",
             badge_class: "badge-error",
             issues: [
               %{severity: :error, code: "invalid_grid", badge_class: "badge-error"},
               %{severity: :warning, code: "unknown_widget_type", badge_class: "badge-warning"}
             ]
           } = PublishValidationPresentation.build(validation)
  end

  test "issue_message explains unsupported operational observables" do
    issue = %{
      code: :unsupported_widget_frame_contract,
      details: %{
        unsupported_observables: ["comms.transport.connection_state"],
        requested_observables: ["comms.transport.connection_state"],
        requested_products: [:connection_state],
        requested_value_kinds: [:state],
        supported_products: [:transport_bitrate, :commanding],
        supported_value_kinds: [:metric]
      }
    }

    assert PublishValidationPresentation.issue_message(issue) ==
             "Widget cannot use selected operational observables: comms.transport.connection_state."

    rows = PublishValidationPresentation.issue_detail_rows(issue)

    assert %{label: "Unsupported observables", value: "comms.transport.connection_state"} in rows
    assert %{label: "Supported products", value: "transport_bitrate, commanding"} in rows
    assert %{label: "Supported value kinds", value: "metric"} in rows
    assert %{label: "Requested products", value: "connection_state"} in rows
    assert %{label: "Requested value kinds", value: "state"} in rows
  end

  test "issue_message explains unsupported binding source" do
    issue = %{
      code: :unsupported_widget_frame_contract,
      details: %{requested_source: :simulation}
    }

    assert PublishValidationPresentation.issue_message(issue) ==
             "Widget cannot use selected binding source: simulation."
  end

  test "issue_message explains invalid runtime default contexts" do
    issue = %{
      code: :invalid_runtime_default_context,
      details: %{context: :data, errors: [:unsupported_data_realm]}
    }

    assert PublishValidationPresentation.issue_message(issue) ==
             "Dashboard runtime defaults include unsupported data context."

    rows = PublishValidationPresentation.issue_detail_rows(issue)

    assert %{label: "Context", value: "data"} in rows
    assert %{label: "Errors", value: "unsupported_data_realm"} in rows
  end

  test "issue_message explains unready publish source requests" do
    issue = %{
      code: :unready_publish_source_request,
      details: %{
        source_warning_code: :unsupported_source_capability,
        source_warning_message: "Source cannot satisfy requested capability",
        details: %{
          logical_source: :telemetry,
          requested_sampling: :latest,
          supported_sampling: []
        }
      }
    }

    assert PublishValidationPresentation.issue_message(issue) ==
             "Dashboard source cannot satisfy a planned widget request."

    rows = PublishValidationPresentation.issue_detail_rows(issue)

    assert %{label: "Source warning", value: "unsupported_source_capability"} in rows

    assert %{label: "Source message", value: "Source cannot satisfy requested capability"} in rows
  end

  test "build adds action hints for source readiness blockers" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :missing_source_binding,
            source_warning_message: "No active binding resolves for telemetry",
            details: %{
              logical_source: :telemetry,
              realm: :rehearsal,
              scope_kind: :spacecraft,
              scope_id: "spacecraft-1"
            }
          }
        }
      ]
    }

    assert %{
             issues: [
               %{
                 action: %{
                   label: "Create or select a source binding",
                   target: "data_sources",
                   message: message,
                   params: %{
                     "logical_source" => "telemetry",
                     "realm" => "rehearsal",
                     "scope_kind" => "spacecraft",
                     "scope_id" => "spacecraft-1",
                     "source_empty_reason" => "missing_source_binding"
                   }
                 }
               }
             ]
           } = PublishValidationPresentation.build(validation)

    assert message =~ "Open Data Sources"
  end

  test "build preserves source capability mismatch details in action params" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
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
          }
        }
      ]
    }

    assert %{
             issues: [
               %{
                 action: %{
                   target: "data_sources",
                   params: %{
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
                   }
                 }
               }
             ]
           } = PublishValidationPresentation.build(validation)
  end

  test "build presents unsupported operational observable scope as dashboard context issue" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :unsupported_observable_scope,
            source_warning_message: "Widget observables do not support selected runtime scope",
            placement_id: "placement-ground-state",
            details: %{
              logical_source: :operational_observables,
              requested_scope_kind: :spacecraft,
              requested_scope_ids: [],
              unsupported_observables: ["ground.station.connection_state"],
              supported_scopes: %{
                "ground.station.connection_state" => [
                  :ground_station,
                  :source_endpoint,
                  :transport,
                  :link
                ]
              }
            }
          }
        }
      ]
    }

    assert %{
             issues: [
               %{
                 id:
                   "error:unready_publish_source_request:placement-ground-state:unsupported_observable_scope:ground.station.connection_state",
                 message:
                   "Dashboard context cannot support selected operational observables: ground.station.connection_state.",
                 summary_rows: [
                   %{key: "placement_id", label: "Placement", value: "placement-ground-state"},
                   %{key: "requested_scope", label: "Context", value: "spacecraft"},
                   %{
                     key: "unsupported_observables",
                     label: "Observables",
                     value: "ground.station.connection_state"
                   }
                 ],
                 action: %{
                   label: "Change widget context",
                   target: "dashboard_editor",
                   params: %{
                     "placement_id" => "placement-ground-state",
                     "logical_source" => "operational_observables",
                     "scope_kind" => "spacecraft",
                     "source_empty_reason" => "unsupported_observable_scope",
                     "unsupported_observables" => "ground.station.connection_state"
                   }
                 }
               }
             ]
           } = PublishValidationPresentation.build(validation)

    rows =
      validation.errors
      |> List.first()
      |> PublishValidationPresentation.issue_detail_rows()

    assert %{label: "Source warning", value: "unsupported_observable_scope"} in rows
    assert %{label: "Placement", value: "placement-ground-state"} in rows
  end

  test "build gives repeated issue codes distinct focus ids" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :invalid_runtime_default_context,
          details: %{context: :time, errors: [:bad_time]}
        },
        %{code: :invalid_runtime_default_context, details: %{context: :data, errors: [:bad_data]}}
      ]
    }

    assert %{
             issues: [
               %{id: "error:invalid_runtime_default_context:time:bad_time"},
               %{id: "error:invalid_runtime_default_context:data:bad_data"}
             ]
           } = PublishValidationPresentation.build(validation)
  end

  test "issue detail rows normalize nils, booleans, numbers, and unknown keys" do
    issue = %{
      details: %{
        custom: nil,
        enabled: false,
        count: 3
      }
    }

    assert PublishValidationPresentation.issue_detail_rows(issue) == [
             %{label: "count", value: "3"},
             %{label: "custom", value: "none"},
             %{label: "enabled", value: "false"}
           ]
  end
end
