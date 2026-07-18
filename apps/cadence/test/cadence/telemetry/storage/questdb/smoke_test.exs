defmodule Cadence.Telemetry.Storage.QuestDB.SmokeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, Smoke}

  @timestamp ~U[2026-06-27 12:00:00Z]
  @timestamp_naive ~N[2026-06-27 12:00:00]

  test "smoke check migrates, writes, reads history, reads decimation, and reads watermark" do
    parent = self()

    exec_fun = fn sql, opts ->
      send(parent, {:questdb_exec, sql, opts})

      cond do
        sql =~ "CREATE TABLE IF NOT EXISTS cadence_schema_migrations" ->
          {:ok, %{"dataset" => []}}

        sql =~ "SELECT version FROM cadence_schema_migrations" ->
          {:ok, %{"dataset" => []}}

        sql =~ "CREATE TABLE IF NOT EXISTS telemetry_observations" ->
          {:ok, %{"dataset" => []}}

        sql =~ "ALTER TABLE telemetry_observations" ->
          {:ok, %{"dataset" => []}}

        sql =~ "INSERT INTO cadence_schema_migrations" ->
          {:ok, %{"dataset" => []}}

        sql =~ "INSERT INTO telemetry_observations" ->
          {:ok, %{"dataset" => []}}

        sql =~ "max(receipt_time) AS latest_receipt_time" ->
          {:ok,
           %{
             "columns" =>
               Enum.map(ObservationReader.watermark_select_columns(), &%{"name" => &1}),
             "dataset" => [[@timestamp_naive, @timestamp_naive, 1]]
           }}

        sql =~ "SAMPLE BY" ->
          {:ok,
           %{
             "columns" =>
               Enum.map(ObservationReader.decimated_select_columns(), &%{"name" => &1}),
             "dataset" => [[@timestamp_naive, 40, 42, 41, 1, "good"]]
           }}

        sql =~ "SELECT sample_id, mission_id, spacecraft_id" ->
          {:ok,
           %{
             "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
             "dataset" => [observation_row()]
           }}

        true ->
          flunk("Unexpected QuestDB SQL:\n#{sql}")
      end
    end

    assert {:ok, result} =
             Smoke.run(
               exec_fun: exec_fun,
               timestamp: @timestamp,
               value: 41,
               sample_id: "sample-smoke-contract",
               mission_id: "mission-smoke-contract",
               point_id: "SMOKE.counter"
             )

    assert result.sample_id == "sample-smoke-contract"
    assert result.mission_id == "mission-smoke-contract"
    assert result.point_id == "SMOKE.counter"
    assert result.value == 41
    assert result.bounded_history_count == 1
    assert result.decimated_bucket_count == 1
    assert result.watermark.sample_count == 1
    assert length(result.applied_migrations) == 3

    sqls = received_sqls([])

    assert_sql_executed(sqls, "CREATE TABLE IF NOT EXISTS cadence_schema_migrations")
    assert_sql_executed(sqls, "CREATE TABLE IF NOT EXISTS telemetry_observations")
    assert_sql_executed(sqls, "ALTER TABLE telemetry_observations")
    assert_sql_executed(sqls, "ADD COLUMN IF NOT EXISTS observation_identity_id STRING")
    assert_sql_executed(sqls, "INSERT INTO telemetry_observations")
    assert_sql_executed(sqls, "SELECT sample_id, mission_id, spacecraft_id")
    assert_sql_executed(sqls, "SAMPLE BY")
    assert_sql_executed(sqls, "max(receipt_time) AS latest_receipt_time")
  end

  defp received_sqls(sqls) do
    receive do
      {:questdb_exec, sql, _opts} -> received_sqls([sql | sqls])
    after
      0 -> Enum.reverse(sqls)
    end
  end

  defp assert_sql_executed(sqls, fragment) do
    assert Enum.any?(sqls, &String.contains?(&1, fragment))
  end

  defp observation_row do
    [
      "sample-smoke-contract",
      "mission-smoke-contract",
      "smoke-spacecraft",
      "SMOKE.counter",
      "SMOKE.counter",
      "smoke-packet-def",
      1,
      "packet-sample-smoke-contract",
      "evidence-sample-smoke-contract",
      "long",
      nil,
      41,
      nil,
      nil,
      "41",
      "good",
      @timestamp_naive,
      @timestamp_naive,
      ~s({"source":"questdb_smoke"}),
      "flight",
      "managed_questdb_primary",
      "managed_telemetry_history",
      "questdb-smoke",
      nil,
      "obs-smoke-contract",
      "obs-ident-smoke-contract",
      "canonical"
    ]
  end
end
