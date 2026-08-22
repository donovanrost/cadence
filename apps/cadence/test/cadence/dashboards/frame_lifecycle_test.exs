defmodule Cadence.Dashboards.FrameLifecycleTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{FrameLifecycle, ResolveWarning}

  test "classifies ready frames when no degradation signals are present" do
    assert %{
             state: :ready,
             severity: :ok,
             reason_codes: [],
             warning_codes: []
           } = FrameLifecycle.classify(%{})
  end

  test "classifies no-data separately from zero or error states" do
    assert %{
             state: :no_data,
             severity: :info,
             reason_codes: [:no_data]
           } = FrameLifecycle.classify(data_state: :no_data)
  end

  test "classifies stale and partial warning codes" do
    assert %{state: :stale, severity: :warning, reason_codes: reasons} =
             FrameLifecycle.classify(warning_codes: [:watermark_unknown])

    assert :watermark_unknown in reasons

    assert %{state: :partial, severity: :warning, reason_codes: reasons} =
             FrameLifecycle.classify(warning_codes: [:partial_data])

    assert :partial_data in reasons
  end

  test "classifies retention gaps as blocking source lifecycle separate from partial data" do
    assert %{state: :retention_gap, severity: :error, reason_codes: reasons} =
             FrameLifecycle.classify(warning_codes: [:retention_gap])

    assert :retention_gap in reasons

    assert %{state: :retention_gap, severity: :error} =
             FrameLifecycle.classify(warning_codes: [:retention_gap], data_state: :no_data)
  end

  test "classifies source errors from warning structs and unsupported capability as strongest" do
    assert %{state: :error, severity: :error, reason_codes: reasons} =
             FrameLifecycle.classify(
               warnings: [
                 %ResolveWarning{code: :source_unavailable, severity: :error}
               ]
             )

    assert :source_unavailable in reasons

    assert %{state: :unsupported, severity: :error, reason_codes: reasons} =
             FrameLifecycle.classify(
               warning_codes: [:source_unavailable, :unsupported_source_capability]
             )

    assert :unsupported_source_capability in reasons
  end

  test "classifies unsupported widget frame contracts as unsupported" do
    assert %{state: :unsupported, severity: :error, reason_codes: reasons} =
             FrameLifecycle.classify(warning_codes: [:unsupported_widget_frame_contract])

    assert :unsupported_widget_frame_contract in reasons
  end
end
