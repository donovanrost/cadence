defmodule Cadence.Dashboards.DataSourcesCachePolicyRuntimeTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.DataSourcesFixtures

  alias Cadence.Dashboards.{EvidenceRef, Frame, SourceRegistry}
  alias Cadence.Management.DataSources

  alias Cadence.DataSources.DataBinding
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  setup do
    persist_mission_scope("org-dash-source", "mission-dash-source")
    :ok
  end

  test "source result frames include selected operational interval evidence" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source_endpoint_scope("endpoint-sc-001")

    assert {:ok, _event} =
             catalog_revision("catalog-revision-a", revision_number: 1)
             |> Event.from_catalog_revision(~U[2026-06-21 20:00:00Z])
             |> OperationalEvents.persist_event()

    binding_set =
      application_binding_set("runtime-apps-a",
        source_endpoint_ref: "endpoint-sc-001",
        apid: 42,
        metric_name: "packets_v1"
      )

    assert {:ok, _binding_set} =
             Cadence.Governance.persist_binding_set("org-dash-source", binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               "org-dash-source",
               "mission-dash-source",
               binding_set.binding_set_id,
               binding_set.version,
               activated_at: ~U[2026-06-21 20:00:00Z]
             )

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, _registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-historical", 12.4, ~U[2026-06-21 20:30:00Z], "evidence-1",
        generation_time: ~U[2026-06-21 20:29:59Z]
      )
    end

    result =
      SourceRegistry.resolve(
        source_request(
          sampling: %{mode: :latest},
          scope_context: %{source_endpoint_id: "endpoint-sc-001"}
        ),
        persisted?: true,
        source_binding_at: ~U[2026-06-21 20:30:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert [%Frame{} = frame] = result.frames

    assert [
             %{kind: :application_binding, subject_id: "runtime-apps-a-packet-counter-rule"},
             %{kind: :binding_set, subject_id: "runtime-apps-a"},
             %{kind: :catalog_revision, subject_id: "catalog-revision-a"}
           ] =
             frame.meta.selected_operational_intervals
             |> Enum.sort_by(& &1.kind)
             |> Enum.map(&Map.take(&1, [:kind, :subject_id]))

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{kind: :binding_set_interval, id: "effective_interval:binding_set:" <> _} ->
               true

             _other ->
               false
           end)

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{
               kind: :application_binding_interval,
               id: "effective_interval:application_binding:" <> _
             } ->
               true

             _other ->
               false
           end)

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{
               kind: :catalog_revision_interval,
               id: "effective_interval:catalog_revision:" <> _
             } ->
               true

             _other ->
               false
           end)
  end
end
