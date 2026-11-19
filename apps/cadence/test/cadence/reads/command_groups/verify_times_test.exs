defmodule Cadence.Reads.CommandGroups.VerifyTimesTest do
  @moduledoc "A member's verification times from its verifier instances (U1, U69 A4a)."
  use ExUnit.Case, async: true

  alias Cadence.Reads.CommandGroups.VerifyTimes

  @t ~U[2026-11-14 07:20:00.000000Z]

  defp at(seconds), do: DateTime.add(@t, seconds)

  defp instance(state, matched, timeout),
    do: %{lifecycle_state: state, matched_at: matched && at(matched), timeout_at: at(timeout)}

  test "verified: the latest match, once every instance is satisfied" do
    row = %{verifier_instances: [instance(:satisfied, 1, 30), instance(:satisfied, 2, 30)]}

    assert %{verify_by: by, verified_at: verified, timed_out_at: nil, failed_at: nil} =
             VerifyTimes.fields(row)

    assert by == at(30) and verified == at(2)
  end

  test "not verified while one is pending; a time-out and a failure name their times" do
    pending = %{verifier_instances: [instance(:satisfied, 1, 30), instance(:pending, nil, 40)]}
    assert %{verified_at: nil, verify_by: by} = VerifyTimes.fields(pending)
    assert by == at(40)

    ended = %{verifier_instances: [instance(:timed_out, nil, 30), instance(:failed, 5, 40)]}

    assert %{verified_at: nil, timed_out_at: timed_out, failed_at: failed} =
             VerifyTimes.fields(ended)

    assert timed_out == at(30) and failed == at(5)
  end

  test "no instances, no times" do
    assert VerifyTimes.fields(nil) == %{
             verify_by: nil,
             verified_at: nil,
             timed_out_at: nil,
             failed_at: nil
           }

    assert VerifyTimes.fields(%{verifier_instances: []}).verified_at == nil
  end
end
