defmodule Cadence.Reads.FleetReceiptsTest do
  @moduledoc """
  What the fleet read asks of the telemetry side (#798): each spacecraft's newest receipt from the
  current-value store without reading its values, and the durable history receipts from a cache.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Reads.FleetStatus
  alias Cadence.Telemetry.{CurrentValueStore, Sample}
  alias Cadence.Telemetry.CurrentValueStore.{ETS, Postgres}

  @mission "mission-fleet-receipts"

  defp sample(craft, point, at, mission \\ @mission) do
    %Sample{
      sample_id: "s-#{mission}-#{craft}-#{point}-#{DateTime.to_unix(at)}",
      mission_id: mission,
      spacecraft_id: craft,
      point_id: point,
      point_name: point,
      packet_definition_id: "pd",
      packet_definition_version: 1,
      packet_id: "pk",
      evidence_id: "ev",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      generation_time: at,
      receipt_time: at,
      provenance: %{}
    }
  end

  @t0 ~U[2026-11-26 10:00:00Z]

  # Times compare as instants (the store keeps microseconds; a sample may carry fewer digits).
  defp instants(receipts),
    do: Map.new(receipts, fn {id, at} -> {id, DateTime.to_unix(at, :microsecond)} end)

  defp at(time), do: DateTime.to_unix(time, :microsecond)

  describe "the ETS store's last receipts" do
    setup do
      table = :"fleet_receipts_#{System.unique_integer([:positive])}"
      policy = CurrentValueStore.policy(module: ETS, table_name: table, name: table)
      start_supervised!(CurrentValueStore.child_spec(policy))
      %{policy: policy}
    end

    test "are the newest per spacecraft, kept as values are recorded", %{policy: policy} do
      :ok =
        CurrentValueStore.record_samples(policy, [
          sample("sc-1", "HK.a", DateTime.add(@t0, 60)),
          sample("sc-1", "HK.b", DateTime.add(@t0, 300)),
          sample("sc-2", "HK.a", @t0),
          sample("sc-9", "HK.a", @t0, "other-mission"),
          sample(nil, "MISSION.x", DateTime.add(@t0, 900))
        ])

      assert policy |> CurrentValueStore.last_receipts(@mission) |> instants() == %{
               "sc-1" => at(DateTime.add(@t0, 300)),
               "sc-2" => at(@t0)
             }

      assert policy |> CurrentValueStore.last_receipts("other-mission") |> instants() ==
               %{"sc-9" => at(@t0)}
    end

    test "an older sample never lowers one, a newer one raises it", %{policy: policy} do
      :ok =
        CurrentValueStore.record_samples(policy, [sample("sc-1", "HK.a", DateTime.add(@t0, 300))])

      :ok = CurrentValueStore.record_samples(policy, [sample("sc-1", "HK.b", @t0)])
      assert %{"sc-1" => latest} = CurrentValueStore.last_receipts(policy, @mission)
      assert DateTime.compare(latest, DateTime.add(@t0, 300)) == :eq

      :ok =
        CurrentValueStore.record_samples(policy, [sample("sc-1", "HK.c", DateTime.add(@t0, 600))])

      assert %{"sc-1" => latest} = CurrentValueStore.last_receipts(policy, @mission)
      assert DateTime.compare(latest, DateTime.add(@t0, 600)) == :eq
    end

    test "agree with what reading every value would say", %{policy: policy} do
      samples =
        for craft <- 1..20, point <- 1..15 do
          sample(
            "sc-#{craft}",
            "HK.p#{point}",
            DateTime.add(@t0, rem(craft * 37 + point * 11, 500))
          )
        end

      :ok = CurrentValueStore.record_samples(policy, samples)

      long_way =
        policy
        |> CurrentValueStore.latest_values_for_mission(@mission, [])
        |> Enum.group_by(& &1.spacecraft_id, & &1.receipt_time)
        |> Map.new(fn {id, times} -> {id, Enum.max(times, DateTime)} end)

      assert policy |> CurrentValueStore.last_receipts(@mission) |> instants() ==
               instants(long_way)
    end

    test "reset clears them with the values", %{policy: policy} do
      :ok = CurrentValueStore.record_samples(policy, [sample("sc-1", "HK.a", @t0)])
      :ok = CurrentValueStore.reset(policy)
      assert CurrentValueStore.last_receipts(policy, @mission) == %{}
    end
  end

  test "the Postgres store groups its rows the same way" do
    Repo.query!("SET LOCAL session_replication_role = replica")

    :ok =
      Postgres.record_samples([
        sample("sc-1", "HK.a", @t0),
        sample("sc-1", "HK.b", DateTime.add(@t0, 120)),
        sample("sc-2", "HK.a", DateTime.add(@t0, 30))
      ])

    assert @mission |> Postgres.last_receipts([]) |> instants() == %{
             "sc-1" => at(DateTime.add(@t0, 120)),
             "sc-2" => at(DateTime.add(@t0, 30))
           }
  end

  describe "the durable receipts cache" do
    setup do
      # Unique per test: a background refresh from another test can land after its cleanup.
      suffix = System.unique_integer([:positive])
      org = "org-fleet-receipts-cache-#{suffix}"
      mission = "mission-fleet-receipts-cache-#{suffix}"
      persist_mission_scope(org, mission)
      saved = Application.get_env(:cadence, :fleet_durable_receipts_ttl_ms)
      key = {FleetStatus, :durable, org, mission}

      on_exit(fn ->
        :persistent_term.erase(key)

        if saved,
          do: Application.put_env(:cadence, :fleet_durable_receipts_ttl_ms, saved),
          else: Application.delete_env(:cadence, :fleet_durable_receipts_ttl_ms)
      end)

      %{org: org, mission: mission}
    end

    defp queries(fun) do
      ref = make_ref()
      me = self()

      :telemetry.attach(
        {__MODULE__, ref},
        [:cadence, :repo, :query],
        fn _event, _m, _meta, _ -> send(me, {ref, :query}) end,
        nil
      )

      fun.()
      Process.sleep(30)
      :telemetry.detach({__MODULE__, ref})
      length(drain(ref, []))
    end

    defp drain(ref, acc) do
      receive do
        {^ref, :query} -> drain(ref, [:query | acc])
      after
        0 -> acc
      end
    end

    test "with a TTL, the history store is asked once and then served from the cache", c do
      Application.put_env(:cadence, :fleet_durable_receipts_ttl_ms, 60_000)
      load = fn -> FleetStatus.last_received_with_status(c.org, c.mission) end

      first = queries(load)
      second = queries(load)
      third = queries(load)

      # The history store's grouped read is among the first load's queries and none of the rest.
      assert second < first
      assert third == second
    end

    test "with no TTL, every read asks the history store", c do
      Application.put_env(:cadence, :fleet_durable_receipts_ttl_ms, 0)
      load = fn -> FleetStatus.last_received_with_status(c.org, c.mission) end
      assert queries(load) == queries(load)
    end

    test "an expired entry is served at once and refreshed in the background", c do
      Application.put_env(:cadence, :fleet_durable_receipts_ttl_ms, 1)
      load = fn -> FleetStatus.last_received_with_status(c.org, c.mission) end
      load.()
      Process.sleep(10)

      # Past its TTL the caller is not made to wait for the store (no grouped read of its own);
      # a task refreshes it.
      assert {_receipts, :ok} = load.()
    end
  end
end
