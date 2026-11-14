defmodule Cadence.Reads.ActionQueue.ContactStartItemTest do
  @moduledoc "U45 contact_start on Now: P1 not_started / P2 missed, due at LOS, holder named."
  use ExUnit.Case, async: true

  alias Cadence.Reads.ActionQueue.{AttentionItems, Item}

  @now ~U[2026-11-14 01:30:00Z]

  defp at(seconds), do: DateTime.add(@now, seconds)

  defp names do
    member = fn id, name ->
      Item.member(%{
        id: id,
        name: name,
        scid: 1,
        plane: 1,
        stale: false,
        last_received_at: nil,
        violating_points: 0
      })
    end

    %{
      spacecraft: %{
        "sc-312" => member.("sc-312", "EARENDIL-312"),
        "sc-047" => member.("sc-047", "EARENDIL-047")
      },
      station: &%{ref: &1, id: "gs-sva", code: "SVA", name: "Svalbard"},
      providers: %{"northlight" => %{id: "northlight", name: "Northlight"}}
    }
  end

  defp start(conflict, holder \\ nil) do
    %{
      id: "rc-312",
      source: "contact_start",
      conflict: conflict,
      state: "open",
      realized_contact_id: "rc-312",
      contact_id: "sc-contact-312",
      spacecraft_id: "sc-312",
      provider_reservation_id: "res-312",
      ground_station_ref: "SVA",
      provider_id: "northlight",
      starts_at: at(-120),
      ends_at: at(360),
      provider_profile_id: "profile-sva",
      provider_profile_name: "Svalbard S-band downlink",
      reason: if(holder, do: "listener_in_use", else: "unknown"),
      holder: holder,
      failure_message: "eaddrinuse",
      retry: "automatic",
      attempts: 3,
      last_attempt_at: at(-10),
      raised_at: at(-110),
      expires_at: nil,
      resolution: nil
    }
  end

  defp holder do
    %{
      realized_contact_id: "rc-047",
      contact_id: "sc-contact-047",
      spacecraft_id: "sc-047",
      provider_reservation_id: "res-047",
      ground_station_ref: "SVA",
      starts_at: at(-1_200),
      ends_at: at(60)
    }
  end

  test "not_started is P1 due at LOS; the holder is named like a pass" do
    %{items: [item]} =
      AttentionItems.build(
        %{items: [start("not_started", holder())], resolved: []},
        names(),
        @now
      )

    assert %{priority: 1, due_at: due, state: :critical} = item
    assert due == at(360)

    assert %{
             source: "contact_start",
             conflict: "not_started",
             reason: "listener_in_use",
             provider_profile_name: "Svalbard S-band downlink",
             retry: "automatic",
             attempts: 3,
             failure_message: "eaddrinuse",
             holder: holder
           } = item.attention

    assert holder == %{
             realized_contact_id: "rc-047",
             contact_id: "sc-contact-047",
             reservation_id: "res-047",
             spacecraft: %{id: "sc-047", name: "EARENDIL-047"},
             station: %{ref: "SVA", id: "gs-sva", code: "SVA", name: "Svalbard"},
             starts_at: at(-1_200),
             ends_at: at(60)
           }

    refute Map.has_key?(item.attention, :reason_sentence)
  end

  test "missed is P2, still due at LOS, with no holder" do
    missed = %{start("missed") | ends_at: at(-60)}
    assert {2, due} = AttentionItems.rank(missed, @now)
    assert due == at(-60)
    assert %{holder: nil, reason: "unknown"} = AttentionItems.object(missed, names())
  end
end
