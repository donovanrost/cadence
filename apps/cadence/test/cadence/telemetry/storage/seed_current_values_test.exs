defmodule Cadence.Telemetry.Storage.SeedCurrentValuesTest do
  @moduledoc """
  Seeding the current-value store from known samples (a recovered snapshot, #831): the store gets
  them as ingest would have recorded them, each with its OWN times, never over a newer value, and
  nothing else is written.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.{CurrentValueStore, Sample, Storage}
  alias Cadence.Telemetry.CurrentValueStore.ETS

  @mission "mission-seed-current-values"

  setup do
    persist_mission_scope("org-seed-current-values", @mission)
    table = :"seed_current_values_#{System.unique_integer([:positive])}"
    cvs = CurrentValueStore.policy(module: ETS, table_name: table, name: table)
    start_supervised!(CurrentValueStore.child_spec(cvs))

    policy =
      Storage.policy(
        [
          writer: Cadence.TestSupport.CapturingTelemetryStorageWriter,
          writer_opts: [test_pid: self()],
          organization_id: "org-seed-current-values",
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        ],
        current_value_store_policy: cvs
      )

    %{policy: policy, cvs: cvs}
  end

  defp sample(id, point, value, receipt) do
    %Sample{
      sample_id: id,
      mission_id: @mission,
      spacecraft_id: "sc-1",
      point_id: point,
      point_name: point,
      packet_definition_id: "pd-1",
      packet_definition_version: 1,
      packet_id: "packet-#{id}",
      evidence_id: "evidence-#{id}",
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: DateTime.add(receipt, -1, :second),
      receipt_time: receipt,
      provenance: %{}
    }
  end

  defp latest(cvs, point) do
    CurrentValueStore.latest_value(cvs, @mission, point, spacecraft_id: "sc-1")
  end

  @old ~U[2026-11-20 10:00:00Z]
  @new ~U[2026-11-26 10:00:00Z]

  test "the store holds the seeded values before any frame, with their own times", c do
    assert latest(c.cvs, "HK.a") == nil

    assert :ok =
             Storage.seed_current_values(
               c.policy,
               [
                 sample("s1", "HK.a", 11, @old),
                 sample("s2", "HK.b", 22, @new)
               ],
               organization_id: "org-seed-current-values"
             )

    assert %Sample{engineering_value: 11, receipt_time: @old} = latest(c.cvs, "HK.a")
    assert %Sample{engineering_value: 22, receipt_time: @new} = latest(c.cvs, "HK.b")

    # Truth before calm: the value is as old as it is, so the staleness rules still say stale.
    assert DateTime.diff(DateTime.utc_now(), latest(c.cvs, "HK.a").receipt_time, :second) > 86_400
  end

  test "it shares the live samples' key: a later live value replaces the seeded one", c do
    :ok =
      Storage.seed_current_values(c.policy, [sample("s1", "HK.a", 1, @old)],
        organization_id: "org-seed-current-values"
      )

    :ok =
      Storage.persist_samples(c.policy, [sample("live", "HK.a", 2, @new)],
        organization_id: "org-seed-current-values"
      )

    assert %Sample{engineering_value: 2, receipt_time: @new} = latest(c.cvs, "HK.a")
    assert length(CurrentValueStore.latest_values_for_mission(c.cvs, @mission, [])) == 1
  end

  test "it never overwrites a newer value the store already has", c do
    :ok =
      Storage.persist_samples(c.policy, [sample("live", "HK.a", 2, @new)],
        organization_id: "org-seed-current-values"
      )

    :ok =
      Storage.seed_current_values(c.policy, [sample("old", "HK.a", 1, @old)],
        organization_id: "org-seed-current-values"
      )

    assert %Sample{engineering_value: 2, receipt_time: @new} = latest(c.cvs, "HK.a")
  end

  test "it writes no observation and publishes nothing", c do
    :ok =
      Storage.seed_current_values(c.policy, [sample("s1", "HK.a", 1, @old)],
        organization_id: "org-seed-current-values"
      )

    refute_receive {:telemetry_storage_envelopes, _}, 20
  end

  test "nothing to seed is nothing", c do
    assert :ok = Storage.seed_current_values(c.policy, [], [])
  end
end
