defmodule Cadence.Dashboards.EvidenceRefTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.EvidenceRef

  test "declares engine evidence vocabularies" do
    assert EvidenceRef.kind?(:raw_evidence)
    assert EvidenceRef.kind?(:limit_definition_lifecycle_event)
    assert EvidenceRef.kind?(:source_request)
    assert EvidenceRef.kind?(:source_watermark_event)
    assert EvidenceRef.kind?(:source_binding_event)
    assert EvidenceRef.kind?(:source_binding_interval)
    assert EvidenceRef.kind?(:source_health_interval)
    assert EvidenceRef.kind?(:binding_set_interval)
    assert EvidenceRef.kind?(:application_binding_interval)
    assert EvidenceRef.kind?(:catalog_revision_interval)
    assert EvidenceRef.kind?(:limit_definition_interval)
    assert EvidenceRef.kind?(:operational_event)
    assert EvidenceRef.kind?(:operational_interval)
    assert EvidenceRef.kind?(:transport_execution_interval)
    assert EvidenceRef.kind?(:command_queue_entry)
    assert EvidenceRef.kind?(:command_release_attempt)
    assert EvidenceRef.kind?(:command_verifier_instance)
    assert EvidenceRef.kind?(:transport_action_request)
    assert EvidenceRef.kind?(:transport_capability_record)

    assert EvidenceRef.source?(:telemetry)
    assert EvidenceRef.source?(:operational_observables)

    assert EvidenceRef.confidence?(:direct)
    assert EvidenceRef.confidence?(:best_effort)

    refute EvidenceRef.kind?(:source)
    refute EvidenceRef.source?(:dashboard)
  end

  test "normalizes persisted or serialized evidence maps into typed refs" do
    assert %EvidenceRef{
             kind: :source_request,
             id: "req-telemetry",
             observed_at: ~U[2026-06-17 12:00:00Z],
             source: :telemetry,
             confidence: :best_effort
           } =
             EvidenceRef.normalize(%{
               "kind" => "source-request",
               "id" => "req-telemetry",
               "observed_at" => ~U[2026-06-17 12:00:00Z],
               "source" => "telemetry",
               "confidence" => "best_effort"
             })
  end

  test "normalizes command queue entry refs from serialized evidence maps" do
    assert %EvidenceRef{
             kind: :command_queue_entry,
             id: "queue-entry-1",
             observed_at: ~U[2026-06-17 12:00:00Z],
             source: :operational_observables,
             confidence: :direct
           } =
             EvidenceRef.normalize(%{
               "kind" => "command_queue_entry",
               "id" => "queue-entry-1",
               "observed_at" => ~U[2026-06-17 12:00:00Z],
               "source" => "operational_observables",
               "confidence" => "direct"
             })
  end

  test "normalizes only evidence-shaped values from lists" do
    ref = %EvidenceRef{kind: :raw_evidence, id: "evidence-1", source: :telemetry}

    assert [
             ^ref,
             %EvidenceRef{
               kind: :limit_event,
               id: "limit-event-1",
               source: :limits,
               confidence: :projected
             }
           ] =
             EvidenceRef.normalize_many([
               ref,
               %{
                 kind: "limit_event",
                 id: "limit-event-1",
                 source: "limits",
                 confidence: "projected"
               },
               "not evidence"
             ])
  end
end
