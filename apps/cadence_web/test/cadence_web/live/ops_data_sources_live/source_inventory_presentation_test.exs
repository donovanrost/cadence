defmodule CadenceWeb.OpsDataSourcesLive.SourceInventoryPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataSource, SourceReadiness}
  alias CadenceWeb.OpsDataSourcesLive.SourceInventoryPresentation

  test "presents sorted source rows with capability, credential, action, and watermark state" do
    sources = [
      %DataSource{
        data_source_id: "source-z",
        adapter: Cadence.Dashboards.Sources.Telemetry,
        kind: :byo_tsdb,
        isolation_level: :org_isolated,
        credentials_ref: "credential-z",
        capabilities: %{latest?: true, range_scan?: true}
      },
      %DataSource{
        data_source_id: "source-a",
        adapter: Cadence.Dashboards.Sources.Telemetry,
        kind: :managed_tsdb,
        isolation_level: :mission_isolated
      }
    ]

    credentials = [
      %{
        credentials_ref: "credential-z",
        status: :active,
        provider: :questdb,
        credential_version: 3,
        metadata: %{http_endpoint: "http://questdb.test"}
      }
    ]

    watermarks = [
      %{
        data_source_id: "source-z",
        observed_at: ~U[2026-07-19 11:00:00Z],
        last_seen_at: nil,
        complete_through: ~U[2026-07-19 10:00:00Z],
        latest_receipt_time: nil,
        confidence: :partial
      },
      %{
        data_source_id: "source-z",
        observed_at: ~U[2026-07-19 12:00:00Z],
        last_seen_at: nil,
        complete_through: ~U[2026-07-19 11:30:00Z],
        latest_receipt_time: nil,
        confidence: :known
      }
    ]

    assert [managed, byo] =
             SourceInventoryPresentation.rows(
               sources,
               credentials,
               [],
               watermarks,
               SourceReadiness.default_policy()
             )

    assert managed.data_source_id == "source-a"
    assert managed.credential_state_text == "none"
    assert managed.supported_sampling_text =~ "latest"
    refute managed.backend_reconcile_action?

    assert byo.data_source_id == "source-z"
    assert byo.credential_ref_text == "credential-z / active v3"
    assert byo.credential_state_text == "active"
    assert byo.credential_provider_text == "questdb"
    assert byo.credential_endpoint_text == "http://questdb.test"
    assert byo.backend_reconcile_action?
    assert byo.backend_deprovision_action?
    assert byo.watermark_text == "2026-07-19T11:30:00Z"
    assert byo.watermark_confidence_text == "known"
  end

  test "marks disabled sources as enableable when deprovision is not pending" do
    source = %DataSource{
      data_source_id: "source-disabled",
      adapter: Cadence.Dashboards.Sources.Limits,
      status: :disabled
    }

    assert [%{enable_action?: true, health_status: "unknown"}] =
             SourceInventoryPresentation.rows(
               [source],
               [],
               [],
               [],
               SourceReadiness.default_policy()
             )
  end
end
