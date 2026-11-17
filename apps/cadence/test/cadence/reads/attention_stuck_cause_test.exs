defmodule Cadence.Reads.AttentionStuckCauseTest do
  # ux U84: only an item whose own cause is the replay-id conflict folds under its Stuck
  # processing item (stuck_processing_id); same contact or same time alone isn't enough.
  use ExUnit.Case, async: true

  alias Cadence.Reads.Attention

  @stuck %{
    id: "rc-1",
    source: "replay_conflict",
    realized_contact_id: "contact-1",
    provider_binding_id: "binding-1",
    stream_key: "contact-1:path-1:binding-1"
  }

  defp settlement(kind),
    do: %{
      id: "s",
      source: "contact_settlement",
      failure_kind: kind,
      realized_contact_id: "contact-1"
    }

  defp backpressure(binding),
    do: %{
      id: "b",
      source: "ingress_backpressure",
      realized_contact_id: "contact-1",
      transport: %{provider_binding_id: binding}
    }

  defp fold(items), do: items |> Attention.one_row_per_cause() |> Map.new(&{&1.id, &1})

  test "a settlement stuck on the conflict and a buffer behind the stuck stream fold under it" do
    folded = fold([@stuck, settlement("replay_id_conflict"), backpressure("binding-1")])

    assert folded["s"].stuck_processing_id == "rc-1"
    assert folded["b"].stuck_processing_id == "rc-1"
    refute Map.has_key?(folded["rc-1"], :stuck_processing_id)
  end

  test "other causes on the same contact don't fold" do
    folded = fold([@stuck, settlement("storage_failed"), backpressure("binding-2")])

    refute Map.has_key?(folded["s"], :stuck_processing_id)
    refute Map.has_key?(folded["b"], :stuck_processing_id)
  end

  test "a partition's item (no stream) folds no settlement; the runtime only behind an apply trip" do
    since = ~U[2026-11-17 03:00:00Z]
    runtime = %{id: "m", source: "mission_runtime", since: since}

    timer = %{
      @stuck
      | id: "rc-t",
        stream_key: nil,
        realized_contact_id: nil,
        provider_binding_id: nil
    }

    starting =
      Map.merge(timer, %{stopped_while: "starting", first_seen_at: ~U[2026-11-17 03:05:00Z]})

    folded = fold([starting, settlement("replay_id_conflict"), runtime])
    refute Map.has_key?(folded["s"], :stuck_processing_id)
    refute Map.has_key?(folded["m"], :stuck_processing_id)

    # An apply that tripped during this not-applied period is its cause.
    applying = %{starting | stopped_while: "applying"}
    assert fold([applying, runtime])["m"].stuck_processing_id == "rc-t"

    # One from before the period began isn't.
    earlier = %{applying | first_seen_at: ~U[2026-11-17 02:00:00Z]}
    refute Map.has_key?(fold([earlier, runtime])["m"], :stuck_processing_id)
  end
end
