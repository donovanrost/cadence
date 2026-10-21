defmodule Cadence.Telemetry.Storage.QuestDB.ObservationRowTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationLine, ObservationRow, ObservationWriter}

  test "insert statement targets telemetry observations with positional params" do
    statement = ObservationRow.insert_statement()

    assert statement =~ "INSERT INTO telemetry_observations"
    assert statement =~ "observed_at, generation_time, receipt_time"
    assert statement =~ "$35"
    assert length(ObservationRow.columns()) == 35
  end

  test "serializes envelope into QuestDB row params" do
    envelope =
      envelope(
        engineering_value: 12.34,
        raw_value: %{counts: 1234},
        provenance: %{packet: :hk, generated_at: ~U[2026-06-17 12:00:00Z]},
        metadata: %{logical_source: :telemetry, labels: [:flight, "primary"]}
      )

    params = ObservationRow.params(envelope)

    assert param(params, :observed_at) == ~N[2026-06-17 12:00:00]
    assert param(params, :generation_time) == ~N[2026-06-17 12:00:00]
    assert param(params, :receipt_time) == ~N[2026-06-17 12:00:03]
    assert param(params, :ingested_at) == ~N[2026-06-17 12:00:05]
    assert param(params, :realm) == "flight"
    assert param(params, :observation_identity_id) == envelope.observation_identity_id
    assert param(params, :value_kind) == "double"
    assert param(params, :value_double) == 12.34
    assert param(params, :value_long) == nil
    assert param(params, :value_bool) == nil
    assert param(params, :value_string) == nil
    assert param(params, :raw_value_text) == ~s({"counts":1234})
    assert param(params, :quality_state) == "good"
    assert param(params, :validity_state) == "canonical"

    assert Jason.decode!(param(params, :provenance_json)) == %{
             "generated_at" => "2026-06-17T12:00:00Z",
             "packet" => "hk"
           }

    assert Jason.decode!(param(params, :metadata_json)) == %{
             "labels" => ["flight", "primary"],
             "logical_source" => "telemetry"
           }
  end

  test "observed_at falls back to receipt time when generation time is missing" do
    envelope = envelope(generation_time: nil, receipt_time: ~U[2026-06-17 12:01:03Z])

    assert ObservationRow.observed_at(envelope) == ~N[2026-06-17 12:01:03]
  end

  test "serializes primitive value types into dedicated columns" do
    assert value_columns(envelope(engineering_value: 42)) == {"long", nil, 42, nil, nil}
    assert value_columns(envelope(engineering_value: true)) == {"bool", nil, nil, true, nil}
    assert value_columns(envelope(engineering_value: "safe")) == {"string", nil, nil, nil, "safe"}
    assert value_columns(envelope(engineering_value: nil)) == {"nil", nil, nil, nil, nil}
  end

  test "preserves unsigned 64-bit counters and reserved LONG null as JSON integers" do
    for value <- [18_446_744_073_709_551_615, -9_223_372_036_854_775_808] do
      assert {"term", nil, nil, nil, encoded} = value_columns(envelope(engineering_value: value))
      assert Jason.decode!(encoded) == value
    end

    assert {"long", nil, 9_223_372_036_854_775_807, nil, nil} =
             value_columns(envelope(engineering_value: 9_223_372_036_854_775_807))
  end

  test "empty QuestDB writes do not open a connection" do
    assert :ok = ObservationWriter.persist_envelopes([])
  end

  test "writer collapses duplicate upsert keys before sending inserts" do
    parent = self()
    retry = envelope(sample_id: "sample-1", envelope_metadata: %{attempt: :retry})
    next_sample = envelope(sample_id: "sample-2", raw_value: 1235)

    exec_fun = fn sql, _opts ->
      send(parent, {:questdb_exec, sql})
      {:ok, %{}}
    end

    assert :ok =
             ObservationWriter.persist_envelopes(
               [envelope(sample_id: "sample-1"), retry, next_sample],
               write_protocol: :sql,
               exec_fun: exec_fun
             )

    assert_receive {:questdb_exec, retry_sql}
    assert retry_sql =~ retry.idempotency_key
    assert retry_sql =~ ~s("attempt":"retry")

    assert retry_sql =~ next_sample.idempotency_key

    refute_receive {:questdb_exec, _sql}
  end

  test "writer bounds encoded batch requests and stops after the first failure" do
    parent = self()
    envelopes = Enum.map(1..100, &envelope(sample_id: "sample-#{&1}", raw_value: &1))

    exec_fun = fn sql, _opts ->
      send(parent, {:batch, sql})
      {:error, :unavailable}
    end

    assert {:error, :unavailable} =
             ObservationWriter.persist_envelopes(envelopes,
               write_protocol: :sql,
               exec_fun: exec_fun
             )

    assert_receive {:batch, sql}
    assert byte_size(URI.encode_www_form(sql)) <= 24_000
    assert sql =~ "sample-1'"
    assert sql =~ "sample-2'"
    refute sql =~ "sample-100'"
    refute_receive {:batch, _sql}
  end

  test "HTTP ingestion preserves typed fields, timestamps, nulls and escaped strings" do
    timestamp = ~U[2026-06-17 12:00:03.123456Z]

    line =
      ObservationLine.encode(
        envelope(
          generation_time: nil,
          receipt_time: timestamp,
          engineering_value: "quoted \"value\"\\path\nnext\rline"
        )
      )

    assert line =~ "receipt_time=#{DateTime.to_unix(timestamp, :microsecond)}t"
    assert String.ends_with?(line, " #{DateTime.to_unix(timestamp, :nanosecond)}\n")
    assert line =~ ~s(value_string="quoted \\"value\\"\\\\path\\)
    assert line =~ "\\\nnext\\\rline"
    refute line =~ "generation_time="
    refute line =~ "value_long="
    assert ObservationLine.encode(envelope(engineering_value: false)) =~ "value_bool=false"
    assert ObservationLine.encode(envelope(engineering_value: 42)) =~ "value_long=42i"
    assert ObservationLine.encode(envelope(engineering_value: 12.34)) =~ "value_double=12.34"
  end

  test "HTTP ingestion batches rows and keeps the last duplicate upsert key" do
    parent = self()
    original = envelope(sample_id: "sample-ilp")
    retry = %{original | engineering_value: 42}
    next_sample = envelope(sample_id: "sample-ilp-next")

    assert :ok =
             ObservationWriter.persist_envelopes([original, retry, next_sample],
               write_fun: fn body, _opts ->
                 send(parent, {:lines, body})
                 :ok
               end
             )

    assert_receive {:lines, body}
    assert length(String.split(body, "\n", trim: true)) == 2
    assert body =~ "value_long=42i"
    refute_receive {:lines, _body}
  end

  test "HTTP ingestion bounds batch size and stops on errors" do
    parent = self()

    envelopes =
      Enum.map(
        1..100,
        &envelope(
          sample_id: "ilp-#{&1}",
          engineering_value: String.duplicate("x", 20_000)
        )
      )

    assert {:error, :unavailable} =
             ObservationWriter.persist_envelopes(envelopes,
               write_fun: fn body, _opts ->
                 send(parent, {:lines, body})
                 {:error, :unavailable}
               end
             )

    assert_receive {:lines, body}
    assert byte_size(body) <= 1_000_000
    assert body =~ ~s(sample_id="ilp-1")
    refute body =~ ~s(sample_id="ilp-100")
    refute_receive {:lines, _body}
  end

  defp value_columns(envelope) do
    params = ObservationRow.params(envelope)

    {
      param(params, :value_kind),
      param(params, :value_double),
      param(params, :value_long),
      param(params, :value_bool),
      param(params, :value_string)
    }
  end

  defp param(params, column) do
    index = Enum.find_index(ObservationRow.columns(), &(&1 == column))
    Enum.at(params, index)
  end

  defp envelope(overrides) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        data_source_id: "ds-managed-questdb",
        binding_id: "binding-flight-telemetry",
        source_endpoint_id: "ksat-downlink",
        recorded_at: ~U[2026-06-17 12:00:05Z],
        metadata: Keyword.get(overrides, :metadata, %{})
      )

    sample_attrs =
      [
        sample_id: Keyword.get(overrides, :sample_id, "sample-1"),
        mission_id: "mission-1",
        spacecraft_id: "sc-1",
        point_id: "HK.battery_voltage",
        point_name: "Battery Voltage",
        packet_definition_id: "packet-def-1",
        packet_definition_version: 1,
        packet_id: "packet-1",
        evidence_id: "evidence-1",
        raw_value: Keyword.get(overrides, :raw_value, 1234),
        engineering_value: Keyword.get(overrides, :engineering_value, 12.34),
        quality_state: :good,
        generation_time: Keyword.get(overrides, :generation_time, ~U[2026-06-17 12:00:00Z]),
        receipt_time: Keyword.get(overrides, :receipt_time, ~U[2026-06-17 12:00:03Z]),
        provenance: Keyword.get(overrides, :provenance, %{})
      ]

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, struct!(Sample, sample_attrs),
        metadata: Keyword.get(overrides, :envelope_metadata, %{})
      )

    envelope
  end
end
