defmodule CadenceWeb.OpsDashboardShowLive.PublishValidationIssueDetailsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.ValidationResult
  alias CadenceWeb.OpsDashboardShowLive.PublishValidationPresentation

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
