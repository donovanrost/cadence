defmodule Cadence.Dashboards.SourceRegistry.ProvenanceTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DataBinding,
    DataBindingInterval,
    DataLink,
    DataSource,
    EvidenceRef,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceFacts,
    SourceResult
  }

  alias Cadence.Dashboards.SourceRegistry.Provenance

  test "shapes binding, interval, segment, and selection metadata" do
    resolved_binding = resolved_binding()

    assert Provenance.binding_metadata(resolved_binding) == %{
             source_binding_id: "binding-1",
             source_binding_version: 3,
             source_binding_event_id: "binding-event-1",
             source_binding_interval: Provenance.interval(resolved_binding),
             source_binding_segment: Provenance.segment(resolved_binding),
             source_selection: %{reason: :active_interval}
           }

    assert Provenance.interval(resolved_binding).data_binding_event_id == "binding-event-1"

    assert %{
             from: ~U[2026-07-19 10:00:00Z],
             to: ~U[2026-07-19 11:00:00Z],
             binding_id: "binding-1",
             interval: %{data_binding_event_id: "binding-event-1"}
           } = Provenance.segment(resolved_binding)
  end

  test "enriches source facts without changing their existing metadata" do
    capability_provenance = %{
      capability_posture: %{sampling: :supported},
      capability_fingerprint: "capability-1"
    }

    facts =
      Provenance.put_facts(
        %SourceFacts{data_revision: "revision-1", meta: %{existing: true}},
        resolved_binding(),
        capability_provenance
      )

    assert facts.data_revision == "revision-1"
    assert facts.meta.existing
    assert facts.meta.source_binding_id == "binding-1"
    assert facts.meta.capability_provenance == capability_provenance
    assert facts.meta.capability_posture == %{sampling: :supported}
  end

  test "enriches results, warnings, frames, fields, and de-duplicates evidence" do
    link = %DataLink{
      label: "Telemetry point",
      target: :telemetry_point,
      target_id: "HK.counter",
      context: %{data: %{existing: true}}
    }

    existing_evidence = %EvidenceRef{
      kind: :source_binding,
      id: "binding-1",
      source: :telemetry
    }

    result =
      Provenance.put_result(
        %SourceResult{
          request_id: "request-1",
          meta: %{existing: true, evidence: [existing_evidence]},
          warnings: [
            %ResolveWarning{
              code: :source_degraded,
              details: %{original: true},
              links: [link]
            }
          ],
          frames: [
            %Frame{
              frame_id: "frame-1",
              source: :telemetry,
              shape: :scalar,
              meta: %{links: [link]},
              fields: [
                %Field{
                  name: "HK.counter",
                  kind: :number,
                  values: [42],
                  metadata: %{links: [link]}
                }
              ]
            }
          ]
        },
        resolved_binding(),
        request(),
        []
      )

    assert result.meta.existing
    assert result.meta.source_binding_id == "binding-1"

    assert Enum.count(
             result.meta.evidence,
             &(&1.kind == :source_binding and &1.id == "binding-1")
           ) == 1

    assert [%ResolveWarning{} = warning] = result.warnings
    assert warning.details.original
    assert warning.details.source_binding_id == "binding-1"
    assert warning_link = hd(warning.links)
    assert warning_link.context.source_request_id == "request-1"
    assert warning_link.context.data.existing
    assert warning_link.context.data.source_binding_id == "binding-1"

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.source_binding_id == "binding-1"
    assert hd(frame.meta.links).context.data.source_binding_id == "binding-1"
    assert [%Field{} = field] = frame.fields
    assert hd(field.metadata.links).context.data.source_binding_id == "binding-1"
  end

  defp request do
    %PlannedSourceRequest{
      request_id: "request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      observables: ["HK.counter"]
    }
  end

  defp resolved_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "binding-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        logical_source: :telemetry,
        data_source_id: "source-1",
        dataset: "flight",
        binding_version: 3,
        current_event_id: "binding-event-1",
        active_from: ~U[2026-07-19 09:00:00Z]
      },
      binding_interval: %DataBindingInterval{
        data_binding_event_id: "binding-event-1",
        binding_id: "binding-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        event_type: :updated,
        status: :active,
        binding_version: 3,
        logical_source: :telemetry,
        realm: :flight,
        data_source_id: "source-1",
        dataset: "flight",
        started_at: ~U[2026-07-19 09:00:00Z],
        active_from: ~U[2026-07-19 09:00:00Z]
      },
      segment_from: ~U[2026-07-19 10:00:00Z],
      segment_to: ~U[2026-07-19 11:00:00Z],
      data_source: %DataSource{data_source_id: "source-1"},
      realm: :flight,
      dataset: "flight",
      source_selection: %{reason: :active_interval}
    }
  end
end
