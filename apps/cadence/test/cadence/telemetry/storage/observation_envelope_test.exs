defmodule Cadence.Telemetry.Storage.ObservationEnvelopeTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}

  test "wraps a telemetry sample with tenant and data source context" do
    context = write_context()
    sample = sample(provenance: %{organization_id: "payload-org"})

    assert {:ok, envelope} = ObservationEnvelope.from_sample(context, sample)

    assert envelope.organization_id == "org-1"
    assert envelope.mission_id == "mission-1"
    assert envelope.realm == :flight
    assert envelope.data_source_id == "ds-managed-questdb"
    assert envelope.binding_id == "binding-flight-telemetry"
    assert envelope.source_endpoint_id == "ksat-downlink"
    assert envelope.observable_id == "HK.battery_voltage"
    assert envelope.validity_state == :canonical
    assert envelope.revision == 1
    assert envelope.ingested_at == ~U[2026-06-16 12:00:05Z]
    assert envelope.provenance.organization_id == "payload-org"
    assert is_binary(envelope.observation_id)
    assert is_binary(envelope.observation_identity_id)
    assert is_binary(envelope.idempotency_key)
  end

  test "uses write context as authoritative tenancy instead of sample provenance" do
    context = write_context(organization_id: "org-authoritative")
    sample = sample(provenance: %{organization_id: "org-from-payload"})

    assert {:ok, envelope} = ObservationEnvelope.from_sample(context, sample)

    assert envelope.organization_id == "org-authoritative"
    assert envelope.provenance.organization_id == "org-from-payload"
  end

  test "rejects samples from a different mission" do
    context = write_context(mission_id: "mission-a")
    sample = sample(mission_id: "mission-b")

    assert {:error, {:mission_mismatch, "mission-a", "mission-b"}} =
             ObservationEnvelope.from_sample(context, sample)
  end

  test "idempotency key is stable for retry of the same source-bound sample" do
    context = write_context()
    sample = sample()

    assert {:ok, first} = ObservationEnvelope.from_sample(context, sample)
    assert {:ok, second} = ObservationEnvelope.from_sample(context, sample)

    assert first.idempotency_key == second.idempotency_key
    assert first.observation_id == second.observation_id
    assert first.observation_identity_id == second.observation_identity_id
  end

  test "observation identity survives alternate path and row identity changes" do
    first_context =
      write_context(data_source_id: "ds-primary", source_endpoint_id: "ksat-downlink")

    alternate_context =
      write_context(data_source_id: "ds-backup", source_endpoint_id: "ssc-downlink")

    first_sample = sample(sample_id: "sample-primary", packet_id: "packet-a", evidence_id: "ev-a")

    alternate_sample =
      sample(sample_id: "sample-backup", packet_id: "packet-b", evidence_id: "ev-b")

    assert {:ok, first} = ObservationEnvelope.from_sample(first_context, first_sample)
    assert {:ok, alternate} = ObservationEnvelope.from_sample(alternate_context, alternate_sample)

    assert first.observation_identity_id == alternate.observation_identity_id
    refute first.observation_id == alternate.observation_id
    refute first.idempotency_key == alternate.idempotency_key
  end

  test "observation identity changes across semantic context but not value revisions" do
    context = write_context(binding_id: "binding-v1")
    reprocessed_context = write_context(binding_id: "binding-v2")

    assert {:ok, first} = ObservationEnvelope.from_sample(context, sample())
    assert {:ok, reprocessed} = ObservationEnvelope.from_sample(reprocessed_context, sample())

    assert {:ok, corrected} =
             ObservationEnvelope.from_sample(
               context,
               sample(sample_id: "sample-corrected", raw_value: 1235),
               revision: 2
             )

    refute first.observation_identity_id == reprocessed.observation_identity_id
    assert first.observation_identity_id == corrected.observation_identity_id
    refute first.observation_id == corrected.observation_id
  end

  test "idempotency key changes across realms and data sources" do
    sample = sample()

    assert {:ok, flight} = ObservationEnvelope.from_sample(write_context(realm: :flight), sample)

    assert {:ok, rehearsal} =
             ObservationEnvelope.from_sample(
               write_context(realm: :rehearsal, data_source_id: "ds-rehearsal"),
               sample
             )

    refute flight.idempotency_key == rehearsal.idempotency_key
    refute flight.observation_id == rehearsal.observation_id
    refute flight.observation_identity_id == rehearsal.observation_identity_id
  end

  test "replay realm requires replay run identity" do
    assert {:error, {:missing_field, :replay_run_id}} =
             [realm: :replay]
             |> write_context_attrs()
             |> WriteContext.new()
  end

  test "supports replay envelopes when replay run identity is supplied" do
    assert {:ok, context} =
             write_context_attrs(realm: :replay, replay_run_id: "replay-run-1")
             |> WriteContext.new()

    assert {:ok, envelope} = ObservationEnvelope.from_sample(context, sample())

    assert envelope.realm == :replay
    assert envelope.replay_run_id == "replay-run-1"
  end

  test "converts envelopes back to samples with storage provenance" do
    context = write_context(data_source_id: "ds-primary", binding_id: "binding-v1")

    assert {:ok, envelope} =
             ObservationEnvelope.from_sample(context, sample(provenance: %{"source" => "test"}),
               validity_state: :conflict,
               revision: 2
             )

    enriched_sample = ObservationEnvelope.to_sample(envelope)

    assert enriched_sample.sample_id == envelope.sample_id
    assert enriched_sample.raw_value == envelope.raw_value
    assert enriched_sample.provenance["source"] == "test"

    assert enriched_sample.provenance["storage"] == %{
             "binding_id" => "binding-v1",
             "data_source_id" => "ds-primary",
             "observation_id" => envelope.observation_id,
             "observation_identity_id" => envelope.observation_identity_id,
             "organization_id" => "org-1",
             "realm" => "flight",
             "replay_run_id" => nil,
             "revision" => 2,
             "source_endpoint_id" => "ksat-downlink",
             "supersedes_observation_id" => nil,
             "validity_state" => "conflict"
           }
  end

  test "builds batches without dropping order" do
    context = write_context()
    first = sample(sample_id: "sample-1", raw_value: 1)
    second = sample(sample_id: "sample-2", raw_value: 2)

    assert {:ok, envelopes} = ObservationEnvelope.batch_from_samples(context, [first, second])

    assert Enum.map(envelopes, & &1.sample_id) == ["sample-1", "sample-2"]
  end

  defp write_context(overrides \\ []) do
    {:ok, context} =
      overrides
      |> write_context_attrs()
      |> WriteContext.new()

    context
  end

  defp write_context_attrs(overrides) do
    Keyword.merge(
      [
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        data_source_id: "ds-managed-questdb",
        binding_id: "binding-flight-telemetry",
        source_endpoint_id: "ksat-downlink",
        recorded_at: ~U[2026-06-16 12:00:05Z],
        metadata: %{logical_source: :telemetry}
      ],
      overrides
    )
  end

  defp sample(overrides \\ []) do
    attrs =
      Keyword.merge(
        [
          sample_id: "sample-1",
          mission_id: "mission-1",
          spacecraft_id: "sc-1",
          point_id: "HK.battery_voltage",
          point_name: "Battery Voltage",
          packet_definition_id: "packet-def-1",
          packet_definition_version: 1,
          packet_id: "packet-1",
          evidence_id: "evidence-1",
          raw_value: 1234,
          engineering_value: 12.34,
          quality_state: :good,
          generation_time: ~U[2026-06-16 12:00:00Z],
          receipt_time: ~U[2026-06-16 12:00:03Z],
          provenance: %{}
        ],
        overrides
      )

    struct!(Sample, attrs)
  end
end
