defmodule Cadence.Limits.StateTextTest do
  use Cadence.UnitCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Limits.{Event, StateText}
  alias Cadence.Limits.Store.{LatestStateRow, LimitEventRow}
  alias Cadence.SemanticRuntime.ThresholdLimits

  @all [:green, :blue, :yellow_low, :yellow_high, :red_low, :red_high]

  test "every state the writers can produce decodes, and the normalized one with it" do
    for state <- @all do
      assert StateText.limit_state(Atom.to_string(state)) == state

      normalized = ThresholdLimits.normalize_state(state)
      assert StateText.normalized_state(Atom.to_string(normalized)) == normalized
    end

    # The vocabulary is the threshold evaluation's, nothing more and nothing less.
    assert Enum.sort(StateText.limit_states()) == Enum.sort(@all)
    assert Enum.sort(StateText.normalized_states()) == [:blue, :green, :red, :yellow]
  end

  test "the decode does not depend on an atom existing: an unknown value is :unknown and logged, never raised" do
    # An atom no module mentions: with String.to_existing_atom this raised ArgumentError.
    text = "never_an_atom_#{System.unique_integer([:positive])}_zzz"

    log =
      capture_log(fn ->
        assert StateText.limit_state(text) == :unknown
        assert StateText.normalized_state(text) == :unknown
      end)

    assert log =~ "unknown stored limit_state"
    assert log =~ "unknown stored normalized_state"
    assert log =~ text
  end

  test "a stored row with an unknown state reads as :unknown instead of failing the read" do
    row = %LatestStateRow{
      limit_event_id: "ev-1",
      mission_id: "m",
      spacecraft_id: "sc-1",
      point_id: "HK.a",
      point_name: "A",
      source_sample_type: "telemetry_sample",
      sample_id: "s",
      limit_definition_id: "d",
      limit_definition_version: 1,
      limit_set_name: "d",
      evaluated_value: nil,
      limit_state: "from_the_future",
      normalized_state: "purple",
      violation: true,
      receipt_time: ~U[2026-11-28 00:00:00.000000Z],
      provenance: %{}
    }

    capture_log(fn ->
      assert %Event{limit_state: :unknown, normalized_state: :unknown, violation: true} =
               LatestStateRow.to_domain(row)

      assert %Event{limit_state: :unknown, normalized_state: :unknown} =
               row
               |> Map.from_struct()
               |> then(&struct(LimitEventRow, &1))
               |> LimitEventRow.to_domain()
    end)

    assert ThresholdLimits.severity(:unknown) == 0
    assert ThresholdLimits.normalize_state(:unknown) == :unknown
  end
end
