defmodule Cadence.Reads.ActionQueue.ListenerRefusalItemTest do
  @moduledoc """
  U50: listener_refusal on Now: P1 when domain says so (not connected, or its own connection
  quiet, in the open window), else P2; due at LOS. Resolved entries say whether a booked pass or a
  hand-started contact ended.
  """
  use ExUnit.Case, async: true

  alias Cadence.Reads.ActionQueue.AttentionItems

  @now ~U[2026-11-14 12:12:00Z]
  defp names,
    do: %{spacecraft: %{}, station: &%{ref: &1, id: nil, code: nil, name: nil}, providers: %{}}

  defp refusal(p1) do
    %{
      id: "rc-008:binding-1",
      source: "listener_refusal",
      conflict: "listener_refusal",
      state: "open",
      raised_at: ~U[2026-11-14 12:11:00Z],
      realized_contact_id: "rc-008",
      contact_id: "sc-008",
      provider_reservation_id: "res-008",
      spacecraft_id: "sc-craft-008",
      ground_station_ref: "SVB",
      provider_id: nil,
      starts_at: ~U[2026-11-14 12:10:57Z],
      ends_at: ~U[2026-11-14 12:18:57Z],
      provider_profile_id: "profile-svb",
      provider_profile_name: "Northlight SVB",
      last_refused_at: ~U[2026-11-14 12:11:40Z],
      refused_count: 3,
      last_refusal: %{reason: "unregistered_scid", scid: 42, peer: "10.0.0.7", at: nil},
      own_quiet_since: nil,
      connected: not p1,
      shared_with: ["rc-007"],
      second_connections_refused: 0,
      p1: p1,
      acknowledged_by: nil,
      resolution: nil,
      expires_at: ~U[2026-11-14 12:18:57Z]
    }
  end

  test "P1 when domain says so, P2 otherwise; due at LOS; the U50 fields go through" do
    for {p1, priority} <- [{true, 1}, {false, 2}] do
      assert {^priority, ~U[2026-11-14 12:18:57Z]} = AttentionItems.rank(refusal(p1), @now)
    end

    object = AttentionItems.object(refusal(true), names())

    assert %{
             source: "listener_refusal",
             conflict: "listener_refusal",
             reservation_id: "res-008",
             refused_count: 3,
             connected: false,
             shared_with: ["rc-007"],
             provider_profile_name: "Northlight SVB",
             last_refusal: %{reason: "unregistered_scid", scid: 42}
           } = object

    refute Map.has_key?(object, :p1)
  end

  test "a resolved entry says whether a booked pass ended; a bare 'system' resolver is a kind" do
    entry = fn reservation ->
      %{
        id: "rc-008:binding-1",
        source: "listener_refusal",
        realized_contact_id: "rc-008",
        provider_reservation_id: reservation,
        resolved_by: "system",
        action: "ended",
        resolved_at: @now
      }
    end

    %{resolved: [booked, hand]} =
      AttentionItems.build(
        %{items: [], resolved: [entry.("res-008"), entry.(nil)]},
        names(),
        @now
      )

    assert %{booked: true, reservation_id: "res-008", resolved_by: %{kind: "system"}} = booked
    assert %{booked: false, reservation_id: nil, action: "ended"} = hand
  end
end
