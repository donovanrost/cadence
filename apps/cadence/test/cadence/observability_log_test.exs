defmodule Cadence.ObservabilityLogTest do
  use Cadence.UnitCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Observability

  test "renders semantic event and active trace correlation metadata" do
    log =
      capture_log(fn ->
        Observability.with_root_span("test.correlated_log", %{}, fn ->
          Observability.log(
            :warning,
            "cadence.test.warning",
            "A correlated warning",
            mission_id: "mission-test",
            source_endpoint_id: nil
          )
        end)
      end)

    assert log =~ "A correlated warning"
    assert log =~ "cadence_event=cadence.test.warning"
    assert log =~ "mission_id=mission-test"
    assert log =~ ~r/otel_trace_id=[0-9a-f]{32}/
    assert log =~ ~r/otel_span_id=[0-9a-f]{16}/
    refute log =~ "source_endpoint_id="
  end

  test "logger formatter exposes the correlation and domain metadata contract" do
    formatter_metadata =
      Application.fetch_env!(:logger, :default_formatter)
      |> Keyword.fetch!(:metadata)

    assert :otel_trace_id in formatter_metadata
    assert :otel_span_id in formatter_metadata
    assert :cadence_event in formatter_metadata
    assert :mission_id in formatter_metadata
    assert :provider_binding_id in formatter_metadata
  end
end
