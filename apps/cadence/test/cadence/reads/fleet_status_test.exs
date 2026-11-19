defmodule Cadence.Reads.FleetStatusTest do
  use ExUnit.Case, async: true

  alias Cadence.Limits.Event
  alias Cadence.Reads.FleetStatus
  alias Cadence.{Spacecraft, SpacecraftType}
  alias Cadence.Telemetry.Sample

  @now ~U[2026-11-08 02:41:17Z]

  defp craft(id, opts \\ []) do
    %Spacecraft{
      spacecraft_id: id,
      mission_id: "m1",
      display_name: Keyword.get(opts, :name, String.upcase(id)),
      scid: Keyword.get(opts, :scid),
      spacecraft_type_id: Keyword.get(opts, :profile_id),
      spacecraft_type_version: Keyword.get(opts, :profile_version),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp limit(spacecraft_id, normalized_state, seconds_ago, opts \\ []) do
    %Event{
      spacecraft_id: spacecraft_id,
      point_id: Keyword.get(opts, :point_id, "p-#{spacecraft_id}"),
      point_name: Keyword.get(opts, :point_name, "VBAT"),
      evaluated_value: Keyword.get(opts, :value, 23.1),
      limit_state: Keyword.get(opts, :limit_state, :red_low),
      normalized_state: normalized_state,
      violation: normalized_state in [:red, :yellow],
      receipt_time: DateTime.add(@now, -seconds_ago)
    }
  end

  defp sample(spacecraft_id, seconds_ago) do
    %Sample{spacecraft_id: spacecraft_id, receipt_time: DateTime.add(@now, -seconds_ago)}
  end

  defp build(input) do
    FleetStatus.build(Map.merge(%{now: @now, stale_after_s: 900}, input))
  end

  test "classifies each spacecraft by worst condition and counts the partition" do
    result =
      build(%{
        spacecraft: [
          craft("crit"),
          craft("caution"),
          craft("stale"),
          craft("ok"),
          craft("never"),
          craft("stale_crit")
        ],
        limit_states: [
          limit("crit", :red, 2),
          limit("crit", :green, 2, point_id: "p2"),
          limit("caution", :yellow, 5),
          limit("ok", :green, 1),
          limit("stale_crit", :red, 3_600)
        ],
        samples: [sample("stale", 1_000), sample("ok", 1)]
      })

    states = Map.new(result.spacecraft, &{&1.id, &1.state})

    assert states == %{
             "crit" => :critical,
             "caution" => :caution,
             "stale" => :stale,
             "ok" => :nominal,
             "never" => :never_heard,
             "stale_crit" => :critical
           }

    assert result.counts == %{
             total: 6,
             critical: 2,
             caution: 1,
             stale: 1,
             nominal: 1,
             never_heard: 1,
             fresh: 3,
             in_contact: nil,
             passes_next_2h: nil
           }

    assert result.stale_after_s == 900
    assert result.last_received_at == DateTime.add(@now, -1)
  end

  describe "build_posture/1 (the top bar's counts, on /counts)" do
    test "counts exactly what build/1 counts, without rows" do
      input = %{
        spacecraft: Enum.map(~w(crit caution stale ok never stale_crit old), &craft/1),
        limit_states: [
          limit("crit", :red, 2),
          limit("caution", :yellow, 5),
          limit("ok", :green, 1),
          limit("stale_crit", :red, 3_600)
        ],
        samples: [sample("stale", 1_000), sample("ok", 1)],
        durable: %{receipts: %{"old" => DateTime.add(@now, -86_400)}, telemetry: :ok}
      }

      posture = build_posture(input)
      fleet = build(input)

      assert posture.counts ==
               Map.take(fleet.counts, [
                 :total,
                 :critical,
                 :caution,
                 :stale,
                 :nominal,
                 :never_heard
               ])

      assert posture.counts == %{
               total: 7,
               critical: 2,
               caution: 1,
               stale: 2,
               nominal: 1,
               never_heard: 1
             }

      assert %{observed_at: @now, telemetry: :ok} = posture
    end

    test "says when the durable store didn't answer; an empty fleet is all zeros" do
      assert %{telemetry: :degraded, counts: %{total: 0, critical: 0, never_heard: 0}} =
               build_posture(%{spacecraft: [], durable: %{receipts: %{}, telemetry: :degraded}})
    end
  end

  defp build_posture(input) do
    FleetStatus.build_posture(Map.merge(%{now: @now, stale_after_s: 900}, input))
  end

  test "a spacecraft heard only in the durable history store is stale, never never_heard" do
    [row] =
      build(%{
        spacecraft: [craft("old")],
        durable_receipts: %{"old" => DateTime.add(@now, -86_400)}
      }).spacecraft

    assert row.state == :stale
    assert row.stale
    assert row.last_received_at == DateTime.add(@now, -86_400)
  end

  test "telemetry is ok by default and degraded when the durable store didn't answer" do
    assert build(%{spacecraft: [craft("a")]}).telemetry == :ok

    assert build(%{spacecraft: [craft("a")], durable: %{receipts: %{}, telemetry: :degraded}}).telemetry ==
             :degraded
  end

  test "reports the worst violating point and freshness per spacecraft" do
    [row] =
      build(%{
        spacecraft: [craft("a")],
        limit_states: [
          limit("a", :yellow, 10, point_id: "temp", point_name: "TEMP", value: 61.0),
          limit("a", :red, 20, point_id: "vbat", point_name: "VBAT", value: 23.1)
        ],
        samples: [sample("a", 4)]
      }).spacecraft

    assert row.limit_state == :critical
    assert row.violating_points == 2
    assert row.worst_point.point_id == "vbat"
    assert row.worst_point.value == 23.1
    assert row.worst_point.limit_state == :critical
    assert row.last_received_at == DateTime.add(@now, -4)
    refute row.stale
  end

  test "surfaces profile names and fleet geometry from metadata, sorted by plane then slot" do
    profile = %SpacecraftType{
      spacecraft_type_id: "prof",
      display_name: "Reflector bus",
      version: 2
    }

    metadata = fn plane, slot ->
      %{
        "plane" => plane,
        "slot" => slot,
        "operational_phase" => "routine",
        "orbit" => %{"mean_anomaly_deg" => 14.4}
      }
    end

    result =
      build(%{
        profiles: [profile],
        spacecraft: [
          craft("b", metadata: metadata.(2, 1), profile_id: "prof", profile_version: 2),
          craft("a", metadata: metadata.("1", 3)),
          craft("z")
        ]
      })

    assert Enum.map(result.spacecraft, & &1.id) == ["a", "b", "z"]
    [a, b, z] = result.spacecraft

    assert {a.plane, a.slot, a.profile} == {1, 3, nil}
    assert b.profile == %{id: "prof", name: "Reflector bus", version: 2}
    assert {b.phase_deg, b.operational_phase} == {14.4, "routine"}
    assert {z.plane, z.slot, z.phase_deg} == {nil, nil, nil}
    assert z.limit_state == :no_data
  end

  test "contact facts: not tracked without bookings, otherwise per row and counted" do
    untracked = build(%{spacecraft: [craft("a")]})
    assert [%{in_contact: nil, next_aos_at: nil, last_los_at: nil}] = untracked.spacecraft
    assert %{in_contact: nil, passes_next_2h: nil} = untracked.counts

    aos = DateTime.add(@now, 600)

    tracked =
      build(%{
        spacecraft: [craft("a"), craft("b")],
        contacts: %{
          tracked?: true,
          passes_next_2h: 3,
          by_spacecraft: %{"a" => %{in_contact: true, next_aos_at: aos, last_los_at: nil}}
        }
      })

    assert [%{id: "a", in_contact: true, next_aos_at: ^aos}, %{id: "b", in_contact: false}] =
             tracked.spacecraft

    assert %{in_contact: 1, passes_next_2h: 3} = tracked.counts
  end
end
