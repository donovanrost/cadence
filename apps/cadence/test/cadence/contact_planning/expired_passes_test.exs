defmodule Cadence.ContactPlanning.ExpiredPassesTest do
  @moduledoc """
  #273: the ONE rule for which selected passes can't be booked any more ('booking window
  closed'), used by the plan read, the approve, the decision record and execution. A pass counts
  as closed when its offer's `expires_at` is within the 60 s lookahead of the decision's `now`, or
  when the provider gave no `expires_at` at all (fail closed: no evidence the window is open).
  """
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.ExpiredPasses

  @now ~U[2026-11-19 10:00:00.000000Z]

  defp pass(id, expires_in_seconds) do
    expires_at = if expires_in_seconds, do: DateTime.add(@now, expires_in_seconds, :second)
    %{contact_opportunity_snapshot_id: id, expires_at: expires_at}
  end

  test "the lookahead: closing within 60 s counts as closed, later is still bookable" do
    set =
      ExpiredPasses.compute([pass("a", -1), pass("b", 59), pass("c", 61), pass("d", 3_600)], @now)

    assert set.ids == ["a", "b"]
    assert set.next_expiry_at == DateTime.add(@now, 1, :second)
    assert ExpiredPasses.margin_seconds() == 60
  end

  test "a pass with no expires_at fails closed: listed, reason no_booking_window" do
    set = ExpiredPasses.compute([pass("open", 3_600), pass("unknown", nil)], @now)

    assert set.ids == ["unknown"]

    assert set.skipped == [
             %{"snapshot_id" => "unknown", "reason" => "no_booking_window"}
           ]
  end

  test "the skipped list names each pass and why, sorted by id" do
    set = ExpiredPasses.compute([pass("z", -5), pass("m", nil), pass("k", 3_600)], @now)

    assert set.skipped == [
             %{"snapshot_id" => "m", "reason" => "no_booking_window"},
             %{"snapshot_id" => "z", "reason" => "opportunity_expired"}
           ]
  end

  test "nothing closed: an empty set, the empty digest, and the next close time" do
    set = ExpiredPasses.compute([pass("a", 600), pass("b", 120)], @now)

    assert set.ids == []
    assert set.digest == ExpiredPasses.digest([])
    assert set.next_expiry_at == DateTime.add(@now, 60, :second)
  end

  test "every pass closed: no next close time" do
    assert %{next_expiry_at: nil} = ExpiredPasses.compute([pass("a", -1), pass("b", 10)], @now)
  end

  # The digest's exact bytes (one definition; api passes it through): lowercase hex SHA-256 of
  # the canonical JSON [1, <sorted ids>]. Literals computed outside Elixir (python3 json.dumps with
  # separators=(",", ":") and hashlib.sha256).
  test "golden digests: empty, one id, and order-independence" do
    assert ExpiredPasses.digest([]) ==
             "1788f993b4772e3516f5409992386cee14668f98ca23773646f1670a8ffaf8d9"

    assert ExpiredPasses.digest(["snap-1"]) ==
             "9369a476715727d5145a3d56b299feb2242d867b49dbbee7e0255d5ca8664f4c"

    assert ExpiredPasses.digest(["b", "a"]) == ExpiredPasses.digest(["a", "b"])
  end

  test "the digest covers the WHOLE set, beyond any response cap (5,001 ids)" do
    ids = for n <- 1..5_001, do: "snap-" <> String.pad_leading(Integer.to_string(n), 5, "0")
    set = ExpiredPasses.compute(Enum.map(ids, &pass(&1, -1)), @now)

    assert length(set.ids) == 5_001
    assert length(set.skipped) == 5_001
    assert set.digest == ExpiredPasses.digest(ids)
  end
end
