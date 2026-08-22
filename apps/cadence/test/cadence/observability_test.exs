defmodule Cadence.ObservabilityTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Observability
  alias Cadence.Observability.AsyncContext
  alias OpenTelemetry.{Span, Tracer}

  test "traces repository queries without capturing SQL statements" do
    handler_function = &OpentelemetryEcto.handle_event/4

    handler =
      [:cadence, :repo, :query]
      |> :telemetry.list_handlers()
      |> Enum.find(&(&1.function == handler_function))

    assert handler
    assert handler.config[:db_statement] == :disabled
  end

  test "propagates an explicit parent context across a process boundary" do
    {parent_span_context, child_span_context, queue_wait_ms} =
      Observability.with_root_span("test.parent", %{}, fn ->
        parent_span_context = Observability.current_span_context()
        async_context = AsyncContext.capture()

        child_span_context =
          Task.async(fn ->
            Observability.with_span(async_context.parent_context, "test.child", %{}, fn ->
              Observability.current_span_context()
            end)
          end)
          |> Task.await()

        {parent_span_context, child_span_context, AsyncContext.queue_wait_ms(async_context)}
      end)

    assert Span.is_valid(parent_span_context)
    assert Span.is_valid(child_span_context)
    assert Span.trace_id(child_span_context) == Span.trace_id(parent_span_context)
    refute Span.span_id(child_span_context) == Span.span_id(parent_span_context)
    assert queue_wait_ms >= 0
  end

  test "builds links only from valid span contexts" do
    first_span_context =
      Observability.with_root_span("test.first", %{}, fn ->
        Observability.current_span_context()
      end)

    second_span_context =
      Observability.with_root_span("test.second", %{}, fn ->
        Observability.current_span_context()
      end)

    links = Observability.links([first_span_context, :undefined, second_span_context])

    assert length(links) == 2

    assert Enum.map(links, & &1.trace_id) == [
             Span.trace_id(first_span_context),
             Span.trace_id(second_span_context)
           ]

    refute Tracer.current_span_ctx() in [first_span_context, second_span_context]
  end

  test "records bounded events on the active span" do
    recorded? =
      Observability.with_root_span("test.events", %{}, fn ->
        Observability.add_event("cadence.test.completed", %{
          "cadence.test.item.count" => 1
        })
      end)

    assert recorded?
    refute Observability.add_event("cadence.test.outside_span")
  end

  test "classifies errors without serializing arbitrary details" do
    assert Observability.error_class(:timeout) == "timeout"
    assert Observability.error_class({:conflict, %{secret: "not rendered"}}) == "conflict"
    assert Observability.error_class(%RuntimeError{}) == "RuntimeError"
    assert Observability.error_class("provider supplied detail") == "unknown"
  end
end
