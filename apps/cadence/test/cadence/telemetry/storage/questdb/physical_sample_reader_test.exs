defmodule Cadence.Telemetry.Storage.QuestDB.PhysicalSampleReaderTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.HistoryStore.QuestDB
  alias Cadence.Telemetry.Storage.QuestDB.PhysicalSampleReader
  alias Cadence.TestSupport.PhysicalSampleFixtures, as: Fixtures

  test "SQL binds exact identity, source, endpoint scope and both clocks before a two-row bound" do
    query =
      Fixtures.query(%{
        sample_id: "sample'$1",
        spacecraft_id: "sc-physical",
        realm: "replay",
        replay_run_id: "run-1",
        source_endpoint_ids: ["endpoint-a", "endpoint-b"],
        receipt_time: ~U[2026-09-08 12:00:05.654321Z],
        from_receipt_time: ~U[2026-09-08 12:00:00Z],
        to_receipt_time: ~U[2026-09-08 12:01:00Z],
        from_observed_at: ~U[2026-09-08 12:00:00.123456Z],
        to_observed_at: ~U[2026-09-08 12:00:00.123456Z]
      })

    assert {:ok, sql} = PhysicalSampleReader.query_sql(query)

    for clause <- [
          "organization_id = 'org-physical'",
          "mission_id = 'mission-physical'",
          "point_id = 'HK.counter'",
          "sample_id = 'sample''$1'",
          "data_source_id = 'source-physical'",
          "binding_id = 'binding-physical'",
          "realm = 'replay'",
          "replay_run_id = 'run-1'",
          "spacecraft_id = 'sc-physical'",
          "source_endpoint_id IN ('endpoint-a', 'endpoint-b')",
          "receipt_time = '2026-09-08T12:00:05.654321Z'",
          "receipt_time >= '2026-09-08T12:00:00Z'",
          "receipt_time <= '2026-09-08T12:01:00Z'",
          "observed_at >= '2026-09-08T12:00:00.123456Z'",
          "observed_at <= '2026-09-08T12:00:00.123456Z'"
        ],
        do: assert(sql =~ clause)

    assert String.ends_with?(sql, "LIMIT 2")
    refute sql =~ "validity_state ="
    refute sql =~ "ORDER BY"
  end

  test "physical read retains raw values, quality and clocks without identity-state lookup" do
    sample = Fixtures.sample()

    policy =
      HistoryStore.policy(module: QuestDB, http_endpoint: "https://selected-source.invalid")

    exec = fn sql, opts ->
      assert sql =~ "sample_id = 'sample-physical'"
      assert opts[:http_endpoint] == "https://selected-source.invalid"
      {:ok, Fixtures.questdb_result([sample])}
    end

    assert {:ok, actual} = HistoryStore.fetch_sample(policy, Fixtures.query(), exec_fun: exec)
    assert actual.sample_id == sample.sample_id
    assert actual.raw_value == sample.raw_value
    assert actual.engineering_value == sample.engineering_value
    assert actual.quality_state == :suspect
    assert actual.receipt_time == sample.receipt_time
    assert actual.generation_time == sample.generation_time
    assert actual.provenance["storage"]["validity_state"] == "superseded"
  end

  test "missing, ambiguous, mismatched, malformed and failed reads remain distinct" do
    sample = Fixtures.sample()

    for {result, expected} <- [
          {{:ok, Fixtures.questdb_result([])}, :not_found},
          {{:ok, Fixtures.questdb_result([sample, sample])}, :ambiguous_physical_sample},
          {{:ok, Fixtures.questdb_result([%{sample | point_id: "other"}])},
           :physical_sample_context_mismatch},
          {{:ok, Fixtures.questdb_result([sample, sample, sample])},
           :invalid_physical_sample_result},
          {{:ok, %{"columns" => [], "dataset" => []}}, :invalid_physical_sample_result},
          {{:error, :offline}, :offline}
        ] do
      assert {:error, ^expected} =
               PhysicalSampleReader.fetch(Fixtures.query(), exec_fun: fn _, _ -> result end)
    end
  end

  test "invalid scope never reaches the HTTP executor" do
    query = %{Fixtures.query() | source_endpoint_ids: []}

    assert {:error, :invalid_physical_sample_query} =
             PhysicalSampleReader.fetch(query,
               exec_fun: fn _, _ -> flunk("unexpected HTTP read") end
             )
  end

  test "rejects corrupt physical clocks, quality, tenant identity and value encodings" do
    result = Fixtures.questdb_result([Fixtures.sample()])
    names = Enum.map(result["columns"], & &1["name"])

    for {field, value, expected} <- [
          {"generation_time", "not-a-clock", :invalid_physical_sample_result},
          {"receipt_time", nil, :invalid_physical_sample_result},
          {"quality_state", "unknown", :invalid_physical_sample_result},
          {"value_kind", "unknown", :invalid_physical_sample_result},
          {"value_double", "12.34", :invalid_physical_sample_result},
          {"organization_id", "foreign", :physical_sample_context_mismatch},
          {"binding_id", "other", :physical_sample_context_mismatch}
        ] do
      row = List.replace_at(hd(result["dataset"]), Enum.find_index(names, &(&1 == field)), value)
      malformed = Map.put(result, "dataset", [row])

      assert {:error, ^expected} =
               PhysicalSampleReader.fetch(Fixtures.query(),
                 exec_fun: fn _, _ -> {:ok, malformed} end
               )
    end
  end
end
