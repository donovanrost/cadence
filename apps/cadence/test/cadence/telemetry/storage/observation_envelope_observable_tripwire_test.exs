defmodule Cadence.Telemetry.Storage.ObservationEnvelopeObservableTripwireTest do
  @moduledoc """
  Tripwire for the identity-state decision seed (11-17). No history backend stores an envelope's
  observable_id, so a row a decision creates sets observable_id = point_id, which is what
  ObservationEnvelope.from_sample writes unless its caller passes :observable_id. No production
  write path does.

  This scan fails when a file that writes envelopes gains an `observable_id:` keyword. A new
  entry here means: check whether it is a write option. If it is, the decision seed
  (DecisionSeed.attrs/4) must read the observable from the stored row instead of assuming it.
  """
  use ExUnit.Case, async: true

  @lib Path.expand("../../../../lib", __DIR__)
  @writes ~r/Storage\.persist_samples\(|ObservationEnvelope\.(from_sample|batch_from_samples)\(/
  @option ~r/\bobservable_id:/

  # Reviewed 11-17: each mentions observable_id: only in an event's attributes, not in write options.
  @reviewed %{
    "cadence/telemetry/storage.ex" => "backfill lifecycle event attrs, built from the envelope",
    "cadence/telemetry/data_management/late_data_policy.ex" =>
      "lifecycle event base_attrs; sample_write_opts has no observable_id"
  }

  test "no envelope write path passes an observable_id option" do
    found =
      Path.join(@lib, "**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        source = File.read!(path)
        Regex.match?(@writes, source) and Regex.match?(@option, source)
      end)
      |> Enum.map(&Path.relative_to(&1, @lib))
      |> Enum.sort()

    assert found == @reviewed |> Map.keys() |> Enum.sort(),
           "envelope writers mentioning observable_id: changed: #{inspect(found)}. " <>
             "If one is a write option, DecisionSeed must read the observable from the row."
  end
end
