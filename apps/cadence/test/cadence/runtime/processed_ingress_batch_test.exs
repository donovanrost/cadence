defmodule Cadence.Runtime.ProcessedIngressBatchTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Observability
  alias Cadence.Runtime.ProcessedIngressBatch

  test "retains trace contexts and persistence queue timing" do
    span_context =
      Observability.with_root_span("test.processed-ingress", %{}, fn ->
        Observability.current_span_context()
      end)

    batch =
      ProcessedIngressBatch.new(%{
        mission_id: "mission-batch",
        realized_contact_id: "contact-batch",
        path_id: "path-batch",
        provider_binding_id: "provider-batch",
        processing_results: [%{outputs: []}],
        trace_contexts: [span_context],
        enqueued_at: System.monotonic_time()
      })

    assert ProcessedIngressBatch.size(batch) == 1
    assert batch.trace_contexts == [span_context]
    assert ProcessedIngressBatch.queue_wait_ms(batch) >= 0
  end
end
