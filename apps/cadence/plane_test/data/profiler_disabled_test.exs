defmodule Cadence.Telemetry.ProfilerDisabledTest do
  use ExUnit.Case, async: true

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.Profiler

  def handle_profiler_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:profiler_event, event, measurements, metadata})
  end

  test "disabled ingress context keeps nested zero-arity instrumentation disabled" do
    raw_evidence =
      RawEvidence.new(%{
        mission_id: "disabled-profiler-context",
        source_ref: "replay/disabled-profiler",
        raw: <<1, 2, 3>>
      })

    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        Profiler.ingress_result_event(),
        &__MODULE__.handle_profiler_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :outer_result =
             Profiler.with_ingress_context(:disabled, raw_evidence, fn ->
               assert :nested_result =
                        Profiler.with_ingress_context(raw_evidence, fn ->
                          assert :runtime_result =
                                   Profiler.with_runtime_component(
                                     raw_evidence.mission_id,
                                     :runtime_boundary,
                                     fn -> :runtime_result end
                                   )

                          assert :ok =
                                   Profiler.record_ingress_result(raw_evidence,
                                     runtime_us: 10,
                                     end_to_end_us: 20
                                   )

                          assert :ok =
                                   Profiler.record_projected_persistence(
                                     raw_evidence.mission_id,
                                     1,
                                     30
                                   )

                          :nested_result
                        end)

               :outer_result
             end)

    assert :ok = Profiler.record_ingress_result(:disabled, raw_evidence, end_to_end_us: 40)

    assert :ok =
             Profiler.record_projected_persistence(
               :disabled,
               raw_evidence.mission_id,
               1,
               50
             )

    refute_receive {:profiler_event, _event, _measurements, _metadata}
  end
end
