defmodule Cadence.Telemetry.Storage.QuestDB.ObservationProvenanceTest do
  @moduledoc """
  Provenance as typed columns (DECISIONS #103, option B): the stored row splits provenance into
  columns + a residual, the reader rebuilds the same map, and the external API's `provenance`
  stays byte-identical to the JSON-only rows, for a packet row and an algorithm-derived row.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}

  alias Cadence.Telemetry.Storage.QuestDB.{
    ObservationProvenance,
    ObservationReader,
    ObservationRow
  }

  @revision "mission_model_revision:732618eedaaa20e92"
  @plan "mission_model_runtime_plan:telemetry:1"
  @algorithm_plan "mission_model_runtime_plan:algorithm:1"
  @container "semantic:container:hk"
  @algorithm "semantic:algorithm:battery_power"

  describe "a packet-derived row" do
    test "stores the model constants as columns, rebuilds ids, and leaves no residual" do
      envelope = envelope(packet_sample())
      row = stored_row(envelope)

      assert row["mission_model_revision_id"] == @revision
      assert row["runtime_plan_id"] == @plan
      assert row["producer_kind"] == "container"
      assert row["producer_id"] == @container
      assert row["semantic_id"] == "semantic:parameter:battery_voltage"
      assert row["qualified_name"] == "/parameters/battery_voltage"
      assert row["identity_ref"] == ~s(["seq",101,477])
      assert row["binding_rule_derived"] == true
      assert row["packet_refs_derived"] == true
      assert row["provenance_json"] == nil
    end

    test "keeps a binding rule id the model doesn't rebuild (an explicit source endpoint)" do
      rule_id = "mission_model_telemetry:#{@revision}:ksat-downlink:#{@container}:rule"
      envelope = envelope(packet_sample(provenance: %{binding_rule_id: rule_id}))
      row = stored_row(envelope)

      assert row["binding_rule_derived"] == false
      assert Jason.decode!(row["provenance_json"]) == %{"binding_rule_id" => rule_id}
      assert rebuilt(row)["binding_rule_id"] == rule_id
    end

    test "keeps packet refs that differ from the row's own columns" do
      envelope = envelope(packet_sample(provenance: %{packet_id: "packet-other"}))
      row = stored_row(envelope)

      assert row["packet_refs_derived"] == false

      assert Jason.decode!(row["provenance_json"]) == %{
               "packet_id" => "packet-other",
               "evidence_id" => "evidence-1"
             }
    end
  end

  describe "an algorithm-derived row" do
    test "promotes only the keys its provenance has; the per-observation keys stay residual" do
      row = stored_row(envelope(algorithm_sample()))

      assert row["producer_kind"] == "algorithm"
      assert row["producer_id"] == @algorithm
      assert row["runtime_plan_id"] == @algorithm_plan
      assert row["semantic_id"] == nil
      assert row["qualified_name"] == nil
      assert row["binding_rule_derived"] == false
      assert row["packet_refs_derived"] == false

      assert Jason.decode!(row["provenance_json"]) == %{
               "source_update_ids" => ["update-1", "update-2"],
               "trigger_sample_id" => "sample-trigger"
             }
    end

    test "a null value stays in the residual as a present key" do
      row = stored_row(envelope(algorithm_sample(provenance: %{runtime_plan_id: nil})))

      assert row["runtime_plan_id"] == nil
      assert Map.fetch!(Jason.decode!(row["provenance_json"]), "runtime_plan_id") == nil
      assert Map.has_key?(rebuilt(row), "runtime_plan_id")
    end
  end

  test "a value that isn't text stays in the residual instead of its column" do
    row = stored_row(envelope(packet_sample(provenance: %{semantic_id: 42})))

    assert row["semantic_id"] == nil
    assert Jason.decode!(row["provenance_json"]) == %{"semantic_id" => 42}
    assert rebuilt(row)["semantic_id"] == 42
  end

  test "a row from before the columns decodes its full JSON as before" do
    envelope = envelope(packet_sample())
    row = legacy_row(envelope)

    assert rebuilt(row) == ObservationProvenance.json_term(envelope.provenance)
  end

  describe "contract: the external API's provenance is byte-identical" do
    for {shape, fun} <- [packet: :packet_sample, algorithm: :algorithm_sample] do
      test "for a #{shape} row" do
        envelope = envelope(apply(__MODULE__, unquote(fun), [[]]))

        assert api_provenance(stored_row(envelope)) == api_provenance(legacy_row(envelope))
      end

      test "for a #{shape} row read, written back and read again" do
        envelope = envelope(apply(__MODULE__, unquote(fun), [[]]))
        first_row = stored_row(envelope)
        first_read = ObservationReader.sample_from_row(first_row)

        # The reader's own bookkeeping is on the read, keyed by the row's identity.
        assert first_read.provenance["storage"]["observation_identity_id"] ==
                 envelope.observation_identity_id

        # Backfill / late data persist the read sample again: its columns come only from the
        # rebuilt map, and the reader's "storage" is never stored.
        second_row = stored_row(envelope(first_read))
        refute Enum.any?(second_row, fn {_column, value} -> stored_storage?(value) end)

        for flag <- ["binding_rule_derived", "packet_refs_derived"],
            do: assert(second_row[flag] == first_row[flag])

        # "storage" describes each read's own row (the write-back is a new row, with its own ids);
        # everything else is byte-identical, and equal to the JSON-only row's.
        assert stored_provenance(second_row) == stored_provenance(first_row)
        assert stored_provenance(second_row) == stored_provenance(legacy_row(envelope))
      end
    end
  end

  def packet_sample(overrides \\ []) do
    provenance =
      Map.merge(
        %{
          evidence_id: "evidence-1",
          packet_id: "packet-1",
          binding_rule_id: ObservationProvenance.binding_rule_id(@revision, "sc-1", @container),
          semantic_id: "semantic:parameter:battery_voltage",
          qualified_name: "/parameters/battery_voltage",
          producer_kind: :container,
          producer_id: @container,
          mission_model_revision_id: @revision,
          runtime_plan_id: @plan
        },
        Map.new(Keyword.get(overrides, :provenance, %{}))
      )

    sample(packet_id: "packet-1", evidence_id: "evidence-1", provenance: provenance)
  end

  def algorithm_sample(overrides \\ []) do
    provenance =
      Map.merge(
        %{
          source_update_ids: ["update-1", "update-2"],
          trigger_sample_id: "sample-trigger",
          mission_model_revision_id: @revision,
          runtime_plan_id: @algorithm_plan,
          producer_kind: :algorithm,
          producer_id: @algorithm
        },
        Map.new(Keyword.get(overrides, :provenance, %{}))
      )

    sample(
      point_id: "DERIVED.battery_power",
      packet_definition_id: "mission_model_algorithm:" <> @algorithm,
      packet_id: "update-3",
      evidence_id: "update-3",
      provenance: provenance
    )
  end

  defp sample(attrs) do
    struct!(
      Sample,
      Keyword.merge(
        [
          sample_id: "sample-1",
          mission_id: "mission-1",
          spacecraft_id: "sc-1",
          point_id: "HK.battery_voltage",
          point_name: "battery_voltage",
          packet_definition_id: @container,
          packet_definition_version: 1,
          packet_id: "packet-1",
          evidence_id: "evidence-1",
          raw_value: 1234,
          engineering_value: 12.34,
          quality_state: :good,
          generation_time: ~U[2026-11-16 18:16:00Z],
          receipt_time: ~U[2026-11-16 18:16:01Z],
          frame_ref: {:seq, 101, 477}
        ],
        attrs
      )
    )
  end

  defp envelope(%Sample{} = sample) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        data_source_id: "ds-managed-questdb",
        binding_id: "binding-flight-telemetry",
        source_endpoint_id: "spacecraft_runtime:sc-1",
        recorded_at: ~U[2026-11-16 18:16:05Z],
        metadata: %{}
      )

    {:ok, envelope} = ObservationEnvelope.from_sample(context, sample)
    envelope
  end

  # The row as the writer stores it (both the line and the SQL path send these params).
  defp stored_row(envelope) do
    ObservationRow.columns()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.zip(ObservationRow.params(envelope))
    |> Map.new()
  end

  # The same observation as a row written before the columns existed: the whole provenance as
  # JSON, the new columns read back null (flags false).
  defp legacy_row(envelope) do
    legacy_json = envelope.provenance |> ObservationProvenance.json_term() |> Jason.encode!()

    envelope
    |> stored_row()
    |> Map.merge(Map.new(ObservationProvenance.select_columns(), &{&1, nil}))
    |> Map.merge(%{
      "binding_rule_derived" => false,
      "packet_refs_derived" => false,
      "provenance_json" => legacy_json
    })
  end

  defp rebuilt(row), do: ObservationProvenance.rebuild(row, &Map.get(row, &1))

  # What GET .../telemetry/points/:id/{latest,history} returns as data[].provenance, as bytes.
  defp api_provenance(row) do
    row
    |> ObservationReader.sample_from_row()
    |> Map.fetch!(:provenance)
    |> JsonDocument.encode()
    |> Jason.encode!()
  end

  defp stored_provenance(row) do
    row
    |> ObservationReader.sample_from_row()
    |> Map.fetch!(:provenance)
    |> Map.delete("storage")
    |> JsonDocument.encode()
    |> Jason.encode!()
  end

  defp stored_storage?(value) when is_binary(value),
    do: match?({:ok, %{"storage" => _}}, Jason.decode(value))

  defp stored_storage?(_value), do: false
end
