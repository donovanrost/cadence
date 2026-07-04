defmodule Cadence.Dashboards.BYOQuestDBSmokeTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{BYOQuestDBSmoke, DataSources, SourceCredentials}
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow}

  @timestamp ~U[2026-06-30 12:00:00Z]
  @timestamp_naive ~N[2026-06-30 12:00:00]
  @organization_id "org-byo-questdb-smoke-test"
  @mission_id "mission-byo-questdb-smoke-test"
  @data_source_id "customer-byo-questdb-smoke-test"
  @binding_id "customer-byo-questdb-smoke-flight-test"
  @credentials_ref "secret://org-byo-questdb-smoke-test/dashboard/customer-questdb"
  @point_id "SMOKE.byo_counter"
  @sample_id "sample-byo-questdb-smoke-contract"
  @http_endpoint "http://customer-questdb-smoke:9000"

  test "smoke resolves env-backed BYO material through probe and dashboard history read" do
    parent = self()

    exec_fun = fn sql, opts ->
      send(parent, {:questdb_exec, sql, opts})
      questdb_response(sql)
    end

    assert {:ok, result} =
             BYOQuestDBSmoke.run(
               start_cadence?: false,
               exec_fun: exec_fun,
               http_endpoint: @http_endpoint,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               binding_id: @binding_id,
               credentials_ref: @credentials_ref,
               point_id: @point_id,
               sample_id: @sample_id,
               timestamp: @timestamp,
               value: 73
             )

    assert result.sample_id == @sample_id
    assert result.organization_id == @organization_id
    assert result.mission_id == @mission_id
    assert result.data_source_id == @data_source_id
    assert result.binding_id == @binding_id
    assert result.point_id == @point_id
    assert result.value == 73
    assert result.http_endpoint == @http_endpoint
    assert result.source_health == :healthy
    assert result.returned_frame_count == 1
    assert length(result.applied_migrations) == 3

    received = received_execs([])

    assert_sql_executed(received, "CREATE TABLE IF NOT EXISTS cadence_schema_migrations")
    assert_sql_executed(received, "CREATE TABLE IF NOT EXISTS telemetry_observations")
    assert_sql_executed(received, "INSERT INTO telemetry_observations")
    assert_sql_executed(received, "SELECT 1")
    assert_sql_executed(received, "FROM telemetry_observations LIMIT 0")
    assert_sql_executed(received, "SELECT sample_id, mission_id, spacecraft_id")

    assert Enum.all?(received, fn {_sql, opts} ->
             opts[:http_endpoint] == @http_endpoint
           end)
  end

  test "cleanup removes smoke source registry records" do
    exec_fun = fn sql, _opts -> questdb_response(sql) end

    assert {:ok, result} =
             BYOQuestDBSmoke.run(
               start_cadence?: false,
               cleanup?: true,
               exec_fun: exec_fun,
               http_endpoint: @http_endpoint,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               binding_id: @binding_id,
               credentials_ref: @credentials_ref,
               point_id: @point_id,
               sample_id: @sample_id,
               timestamp: @timestamp,
               value: 73
             )

    assert result.cleanup?
    assert result.data_source_id == @data_source_id
    assert {:error, :data_source_not_found} = DataSources.fetch_data_source(@data_source_id)
    assert {:error, :data_binding_not_found} = DataSources.fetch_data_binding(@binding_id)

    assert {:error, :credential_reference_not_found} =
             SourceCredentials.fetch_reference(@credentials_ref)
  end

  test "retries dashboard history read until the external write is visible" do
    parent = self()
    {:ok, history_attempts} = Agent.start_link(fn -> 0 end)

    exec_fun = fn sql, opts ->
      send(parent, {:questdb_exec, sql, opts})

      if history_sample_query?(sql) do
        attempt = Agent.get_and_update(history_attempts, &{&1 + 1, &1 + 1})

        case attempt do
          1 -> empty_history_response()
          _attempt -> questdb_response(sql)
        end
      else
        questdb_response(sql)
      end
    end

    assert {:ok, result} =
             BYOQuestDBSmoke.run(
               start_cadence?: false,
               exec_fun: exec_fun,
               http_endpoint: @http_endpoint,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               binding_id: @binding_id,
               credentials_ref: @credentials_ref,
               point_id: @point_id,
               sample_id: @sample_id,
               timestamp: @timestamp,
               value: 73,
               history_read_attempts: 2,
               history_retry_sleep_ms: 0
             )

    assert result.sample_id == @sample_id

    history_queries =
      received_execs([])
      |> Enum.filter(fn {sql, _opts} -> history_sample_query?(sql) end)

    assert length(history_queries) == 2
  end

  defp received_execs(exec_calls) do
    receive do
      {:questdb_exec, sql, opts} -> received_execs([{sql, opts} | exec_calls])
    after
      0 -> Enum.reverse(exec_calls)
    end
  end

  defp assert_sql_executed(exec_calls, fragment) do
    assert Enum.any?(exec_calls, fn {sql, _opts} -> String.contains?(sql, fragment) end)
  end

  defp questdb_response(sql) do
    case {migration_response(sql), probe_response(sql), read_response(sql)} do
      {{:ok, _body} = response, _probe, _read} -> response
      {nil, {:ok, _body} = response, _read} -> response
      {nil, nil, {:ok, _body} = response} -> response
      {nil, nil, nil} -> flunk("Unexpected QuestDB SQL:\n#{sql}")
    end
  end

  defp migration_response(sql) do
    if sql =~ "cadence_schema_migrations" or
         sql =~ "CREATE TABLE IF NOT EXISTS telemetry_observations" or
         sql =~ "ALTER TABLE telemetry_observations" or
         sql =~ "INSERT INTO telemetry_observations" do
      {:ok, %{"dataset" => []}}
    end
  end

  defp probe_response("SELECT 1"),
    do: {:ok, %{"columns" => [%{"name" => "1"}], "dataset" => [[1]]}}

  defp probe_response(sql) do
    if sql =~ "FROM telemetry_observations LIMIT 0" do
      {:ok, %{"columns" => questdb_probe_columns(), "dataset" => []}}
    end
  end

  defp read_response(sql) do
    cond do
      sql =~ "max(receipt_time) AS latest_receipt_time" ->
        {:ok,
         %{
           "columns" => Enum.map(ObservationReader.watermark_select_columns(), &%{"name" => &1}),
           "dataset" => [[@timestamp_naive, @timestamp_naive, 1]]
         }}

      sql =~ "SELECT sample_id, mission_id, spacecraft_id" ->
        {:ok,
         %{
           "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
           "dataset" => [observation_row()]
         }}

      true ->
        nil
    end
  end

  defp history_sample_query?(sql) do
    String.contains?(sql, "SELECT sample_id, mission_id, spacecraft_id") and
      String.contains?(sql, "ORDER BY receipt_time")
  end

  defp empty_history_response do
    {:ok,
     %{
       "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
       "dataset" => []
     }}
  end

  defp questdb_probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
    |> Enum.map(&%{"name" => &1})
  end

  defp observation_row do
    [
      @sample_id,
      @mission_id,
      "smoke-spacecraft",
      @point_id,
      @point_id,
      "byo-smoke-packet-def",
      1,
      "packet-#{@sample_id}",
      "evidence-#{@sample_id}",
      "long",
      nil,
      73,
      nil,
      nil,
      "73",
      "good",
      @timestamp_naive,
      @timestamp_naive,
      ~s({"source":"byo_questdb_smoke"}),
      "flight",
      @data_source_id,
      @binding_id,
      "questdb-byo-smoke",
      nil,
      "obs-byo-smoke-contract",
      "obs-ident-byo-smoke-contract",
      "canonical"
    ]
  end
end
