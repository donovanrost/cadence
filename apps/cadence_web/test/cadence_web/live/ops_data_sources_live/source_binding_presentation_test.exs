defmodule CadenceWeb.OpsDataSourcesLive.SourceBindingPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.SourceReadiness

  alias Cadence.DataSources.{DataBinding, DataSource}
  alias CadenceWeb.OpsDataSourcesLive.SourceBindingPresentation

  test "groups bindings and orders active rows before missing disabled rows" do
    source = %DataSource{
      data_source_id: "source-1",
      adapter: Cadence.Dashboards.Sources.Telemetry,
      credentials_ref: "credential-1",
      isolation_level: :mission_isolated
    }

    credentials = [
      %{credentials_ref: "credential-1", status: :active, credential_version: 2}
    ]

    bindings = [
      binding("binding-disabled", "retired-source", :disabled),
      binding("binding-active", "source-1", :active)
    ]

    assert [
             %{
               id: "telemetry-flight",
               logical_source_text: "telemetry",
               realm_text: "flight",
               group_status: "active",
               rows: [active, disabled]
             }
           ] =
             SourceBindingPresentation.groups(
               bindings,
               [source],
               credentials,
               [],
               SourceReadiness.default_policy()
             )

    assert active.binding.binding_id == "binding-active"
    assert active.source_status_text == "active"
    assert active.source_adapter_text == "Cadence.Dashboards.Sources.Telemetry"
    assert active.credential_ref_text == "credential-1 / active v2"

    assert disabled.binding.binding_id == "binding-disabled"
    assert disabled.source_status_text == "missing"
    assert disabled.credential_ref_text == "missing"
  end

  test "formats readiness policy values for page metadata" do
    assert %{
             policy_id: "default",
             block_source_health: "unavailable",
             block_freshness: "fresh",
             block_connection_test: "failed blocked"
           } =
             SourceBindingPresentation.readiness_policy_row(SourceReadiness.default_policy())
  end

  defp binding(binding_id, data_source_id, status) do
    %DataBinding{
      binding_id: binding_id,
      logical_source: :telemetry,
      realm: :flight,
      data_source_id: data_source_id,
      status: status
    }
  end
end
