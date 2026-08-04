defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.DataSources.DataSource

  alias CadenceWeb.OpsDataSourcesLive.{
    SourceFocus,
    SourceFocusPresentation
  }

  describe "evidence/1" do
    test "omits evidence when the focus has no evidence selection" do
      assert SourceFocusPresentation.evidence(SourceFocus.default()) == nil
    end

    test "derives stale evidence presentation and source identity" do
      focus =
        SourceFocus.from_params(%{
          "data_source_id" => "source-1",
          "source_binding_id" => "binding-1",
          "source_empty_reason" => "stale_data",
          "selected_evidence_kind" => "source",
          "selected_source_evidence_mode" => "health"
        })

      assert %{
               kind: "source",
               mode: "health",
               state: "stale",
               reason: "stale_data",
               title: "Source freshness evidence is stale",
               detail: detail
             } = SourceFocusPresentation.evidence(focus)

      assert detail =~ "source=binding-1->source-1"
    end
  end

  describe "remediation/2" do
    test "directs missing binding focus to source registration" do
      focus =
        SourceFocus.from_params(%{
          "logical_source" => "telemetry",
          "realm" => "flight",
          "source_empty_reason" => "missing_source_binding"
        })

      assert %{
               kind: "missing_source_binding",
               action: :register_source,
               target: "source_registration",
               target_id: nil,
               capability_rows: [],
               candidate_rows: []
             } = SourceFocusPresentation.remediation(focus, [])
    end

    test "uses the matched source as the review target" do
      focus =
        SourceFocus.from_params(%{"source_empty_reason" => "disabled_data_source"})

      focus = %{focus | matched_data_source_id: "source-1"}

      assert %{
               kind: "disabled_data_source",
               action: :review_source,
               target: "source",
               target_id: "source-1"
             } = SourceFocusPresentation.remediation(focus, [])
    end

    test "orders compatible capability candidates before blocked candidates" do
      focus =
        SourceFocus.from_params(%{
          "logical_source" => "telemetry",
          "source_empty_reason" => "unsupported_source_capability",
          "requested_sampling" => "bounded_history",
          "supported_sampling" => "latest",
          "requested_products" => "bounded_receipt_time_history",
          "supported_products" => "latest_value"
        })

      focus = %{focus | matched_source_binding_id: "binding-1"}

      sources = [
        telemetry_source("latest", %{range_scan?: false, supported_products: [:latest_value]}),
        telemetry_source("history", %{
          range_scan?: true,
          supported_products: [:bounded_receipt_time_history]
        }),
        %DataSource{
          data_source_id: "limits",
          adapter: Cadence.Dashboards.Sources.Limits
        }
      ]

      assert %{
               kind: "unsupported_source_capability",
               action: :review_binding,
               target_id: "binding-1",
               capability_rows: capability_rows,
               candidate_rows: [compatible, blocked]
             } = SourceFocusPresentation.remediation(focus, sources)

      assert Enum.map(capability_rows, & &1.key) == ["sampling", "products", "source_products"]
      assert compatible.data_source_id == "history"
      assert compatible.compatible?
      assert blocked.data_source_id == "latest"
      refute blocked.compatible?
      assert blocked.missing_text =~ "sampling=bounded_history"
    end
  end

  defp telemetry_source(data_source_id, capabilities) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: capabilities
    }
  end
end
