defmodule Cadence.Telemetry.Storage.QuestDB.RetentionQuestDBTest do
  @moduledoc """
  The retention against a REAL QuestDB (#693): it pins what the unit tests take on faith from the
  docs, namely `table_partitions`' column names, `maxTimestamp`'s format, `active`, and the
  `DROP PARTITION LIST` syntax. Runs in CI's questdb-integration job (`mix test --only questdb`).

  The rows are on 2020 days, far from anything else the suite writes, and `now` is passed in, so
  the run expires only those.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.QuestDBCase

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, Retention}

  @moduletag :questdb

  @oldest "2020-02-10"
  @middle "2020-02-11"
  @newest "2020-02-12"

  setup :setup_questdb

  setup do
    # Leave nothing behind for a rerun or another test (the newest partition cannot be dropped
    # while it is the table's last, which it is not: today's is).
    on_exit(fn ->
      RestClient.exec(
        "ALTER TABLE telemetry_observations DROP PARTITION LIST '#{@oldest}', '#{@middle}', '#{@newest}'",
        []
      )
    end)

    :ok
  end

  test "drops the day partitions past retention and keeps the newer ones" do
    mission = "mission-retention-questdb-#{System.unique_integer([:positive])}"

    write_observations!([
      envelope(mission, "old", ~U[2020-02-10 08:00:00Z]),
      envelope(mission, "mid", ~U[2020-02-11 08:00:00Z]),
      envelope(mission, "new", ~U[2020-02-12 08:00:00Z])
    ])

    # The WAL applies asynchronously: wait until all three partitions exist.
    present = read_back(fn -> all_present(partition_names()) end)
    assert Enum.all?([@oldest, @middle, @newest], &(&1 in present))

    # Two days of retention at noon on the newest day: the cutoff is noon on the oldest day, so
    # only the oldest partition (last row 08:00) is wholly before it.
    assert {:ok, report} =
             Retention.run(
               now: ~U[2020-02-12 12:00:00Z],
               settings: [retention_days: 2]
             )

    # Anything older that another test left in the shared table goes too; the middle and newest
    # days never do.
    assert @oldest in report.dropped
    refute @middle in report.dropped
    refute @newest in report.dropped
    assert report.disk_bytes > 0

    # The table is a WAL table, so the drop is applied asynchronously, like the inserts above:
    # wait for it, then check what remains.
    names = read_back(fn -> oldest_gone(partition_names()) end)
    refute @oldest in names
    assert @middle in names
    assert @newest in names
  end

  defp partition_names do
    {:ok, %{"dataset" => rows}} =
      RestClient.exec(
        "SELECT name FROM table_partitions('telemetry_observations') ORDER BY name",
        []
      )

    List.flatten(rows)
  end

  defp oldest_gone(names), do: if(@oldest in names, do: names, else: {:ok, names})

  defp all_present(names) do
    if Enum.all?([@oldest, @middle, @newest], &(&1 in names)), do: {:ok, names}, else: names
  end

  defp envelope(mission, id, generated_at) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-retention-questdb",
        mission_id: mission,
        realm: :flight,
        data_source_id: "ds-retention",
        binding_id: "binding-retention",
        source_endpoint_id: "station-retention",
        recorded_at: generated_at,
        metadata: %{}
      )

    sample = %Sample{
      sample_id: "retention-#{id}-#{mission}",
      mission_id: mission,
      spacecraft_id: "sc-retention",
      point_id: "HK.retention",
      point_name: "HK.retention",
      packet_definition_id: "packet-def-retention",
      packet_definition_version: 1,
      packet_id: "packet-#{id}",
      evidence_id: "evidence-#{id}",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      generation_time: generated_at,
      receipt_time: generated_at,
      provenance: %{}
    }

    {:ok, envelope} = ObservationEnvelope.from_sample(context, sample, validity_state: :canonical)
    envelope
  end
end
