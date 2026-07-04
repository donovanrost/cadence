defmodule Cadence.Telemetry.Storage.QuestDB.ObservationRowTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationRow, ObservationWriter}

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
               exec_fun: exec_fun
             )

    assert_receive {:questdb_exec, retry_sql}
    assert retry_sql =~ retry.idempotency_key
    assert retry_sql =~ ~s("attempt":"retry")

    assert_receive {:questdb_exec, next_sample_sql}
    assert next_sample_sql =~ next_sample.idempotency_key

    refute_receive {:questdb_exec, _sql}
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
