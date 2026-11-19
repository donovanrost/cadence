defmodule Cadence.Telemetry.Storage.QuestDB.ObservationProvenanceQuestDBTest do
  @moduledoc """
  Provenance as typed columns (DECISIONS #103) against a REAL QuestDB: the migration gives the
  columns their types, a downlink's packet rows land in them (production path: TCP → journal →
  `Writers.QuestDB`), and an algorithm row and a JSON-only row from before the columns read back
  to the same provenance.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.QuestDBCase
  import Cadence.TestSupport.TCPContactFixture

  alias Cadence.Catalog.TelemetryBinding
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}

  alias Cadence.Telemetry.Storage.QuestDB.{
    ObservationProvenance,
    ObservationReader,
    ObservationRow,
    RestClient,
    SQL
  }

  @moduletag :questdb

  setup :setup_questdb

  test "the migration gives the provenance columns their types and dictionary settings" do
    {:ok, %{"dataset" => rows}} =
      RestClient.exec(
        ~s[SELECT "column", type, symbolCached, symbolCapacity ] <>
          ~s[FROM table_columns('telemetry_observations')],
        []
      )

    columns = Map.new(rows, fn [name | rest] -> {name, rest} end)

    assert columns["semantic_id"] == ["SYMBOL", false, 262_144]
    assert columns["qualified_name"] == ["SYMBOL", false, 262_144]
    assert columns["producer_id"] == ["SYMBOL", true, 16_384]
    assert columns["mission_model_revision_id"] == ["SYMBOL", true, 16_384]
    assert columns["runtime_plan_id"] == ["SYMBOL", true, 32_768]
    assert columns["producer_kind"] == ["SYMBOL", true, 256]
    assert hd(columns["identity_ref"]) == "VARCHAR"
    assert hd(columns["binding_rule_derived"]) == "BOOLEAN"
    assert hd(columns["packet_refs_derived"]) == "BOOLEAN"
  end

  test "a downlink's packet rows store the model constants in columns, not JSON", c do
    contact = start_tcp_contact!()

    columns =
      ~w(sample_id packet_id semantic_id qualified_name producer_kind producer_id
         mission_model_revision_id runtime_plan_id identity_ref binding_rule_derived
         packet_refs_derived provenance_json)

    ingest_frames!(contact, 400..402, c.questdb_since)
    rows = rows(contact.mission_id, c.questdb_since, columns)

    assert rows != []

    for row <- rows do
      assert row["producer_kind"] == "container"
      assert String.starts_with?(row["semantic_id"], "semantic:parameter:")
      assert is_binary(row["qualified_name"]) and is_binary(row["producer_id"])
      assert is_binary(row["mission_model_revision_id"]) and is_binary(row["runtime_plan_id"])
      assert ["seq", _apid, _count] = Jason.decode!(row["identity_ref"])
      assert row["packet_refs_derived"] == true

      # The fixture binds its packets with its own rule ids (e.g. "bp-rule-645"), not the
      # model's spacecraft_runtime:SC format, so they are NOT rebuildable by construction:
      # exactly that id stays in the residual (case b). The derivable case is the next test.
      assert %{"binding_rule_id" => rule_id} = Jason.decode!(row["provenance_json"])
      assert map_size(Jason.decode!(row["provenance_json"])) == 1
      assert is_binary(rule_id) and rule_id != ""
      assert row["binding_rule_derived"] == false
    end

    [sample | _rest] = read_samples(contact.mission_id)
    assert sample.provenance["semantic_id"] =~ "semantic:parameter:"
    assert sample.provenance["packet_id"] == sample.packet_id
    assert is_binary(sample.provenance["binding_rule_id"])
    assert sample.provenance["storage"]["observation_identity_id"]
  end

  test "a packet row whose binding id the model rebuilds stores no residual and reads identically" do
    mission_id = "mission-provenance-#{System.unique_integer([:positive])}"
    revision = "mission_model_revision:provenance"
    producer = "semantic:container:hk"

    provenance = %{
      evidence_id: "evidence-1",
      packet_id: "packet-1",
      binding_rule_id: TelemetryBinding.binding_rule_id(revision, "sc-1", producer),
      semantic_id: "semantic:parameter:battery_voltage",
      qualified_name: "/parameters/battery_voltage",
      producer_kind: :container,
      producer_id: producer,
      mission_model_revision_id: revision,
      runtime_plan_id: "mission_model_runtime_plan:telemetry:1"
    }

    packet = fn sample_id ->
      envelope(mission_id, sample_id,
        packet_id: "packet-1",
        evidence_id: "evidence-1",
        packet_definition_id: producer,
        provenance: provenance
      )
    end

    write_observations!([packet.("sample-derived")])
    insert_legacy!(packet.("sample-legacy"))

    samples = read_two(mission_id)

    [row] =
      read_back(fn ->
        case rows(mission_id, DateTime.add(DateTime.utc_now(), -300, :second), [
               "sample_id",
               "provenance_json",
               "binding_rule_derived",
               "packet_refs_derived"
             ]) do
          rows when is_list(rows) ->
            case Enum.filter(rows, &(&1["sample_id"] == "sample-derived")) do
              [_row] = found -> {:ok, found}
              other -> other
            end
        end
      end)

    assert row["provenance_json"] == nil
    assert row["binding_rule_derived"] == true
    assert row["packet_refs_derived"] == true

    by_id = Map.new(samples, &{&1.sample_id, &1})
    assert stored(by_id["sample-derived"]) == stored(by_id["sample-legacy"])
    assert by_id["sample-derived"].provenance["binding_rule_id"] == provenance.binding_rule_id
  end

  test "an algorithm row and a JSON-only row from before the columns read the same provenance" do
    mission_id = "mission-provenance-#{System.unique_integer([:positive])}"
    envelope = envelope(mission_id, "sample-new")
    legacy = envelope(mission_id, "sample-legacy")

    write_observations!([envelope])
    insert_legacy!(legacy)

    samples = read_two(mission_id)

    by_id = Map.new(samples, &{&1.sample_id, &1})
    assert stored(by_id["sample-new"]) == stored(by_id["sample-legacy"])
    assert by_id["sample-new"].provenance["source_update_ids"] == ["update-1", "update-2"]
    refute Map.has_key?(by_id["sample-new"].provenance, "semantic_id")
  end

  defp envelope(mission_id, sample_id, overrides \\ []) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-provenance",
        mission_id: mission_id,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "binding-provenance",
        source_endpoint_id: "spacecraft_runtime:sc-1",
        recorded_at: DateTime.utc_now(),
        metadata: %{}
      )

    sample =
      struct!(
        %Sample{
          sample_id: sample_id,
          mission_id: mission_id,
          spacecraft_id: "sc-1",
          point_id: "DERIVED.battery_power",
          point_name: "battery_power",
          packet_definition_id: "mission_model_algorithm:semantic:algorithm:battery_power",
          packet_definition_version: 1,
          packet_id: "update-" <> sample_id,
          evidence_id: "update-" <> sample_id,
          raw_value: nil,
          engineering_value: 41.5,
          quality_state: :good,
          generation_time: DateTime.utc_now(),
          receipt_time: DateTime.utc_now(),
          frame_ref: {:seq, 101, 477},
          provenance: %{
            source_update_ids: ["update-1", "update-2"],
            trigger_sample_id: "sample-trigger",
            mission_model_revision_id: "mission_model_revision:provenance",
            runtime_plan_id: nil,
            producer_kind: :algorithm,
            producer_id: "semantic:algorithm:battery_power"
          }
        },
        overrides
      )

    {:ok, envelope} = ObservationEnvelope.from_sample(context, sample)
    envelope
  end

  # The row as a build before the columns wrote it: the whole provenance as JSON, no columns.
  defp insert_legacy!(envelope) do
    full_json = envelope.provenance |> ObservationProvenance.json_term() |> Jason.encode!()
    provenance_columns = ObservationProvenance.columns()

    {columns, values} =
      ObservationRow.columns()
      |> Enum.zip(ObservationRow.params(envelope))
      |> Enum.reject(fn {column, _value} -> column in provenance_columns end)
      |> Enum.map(fn
        {:provenance_json, _residual} -> {:provenance_json, full_json}
        pair -> pair
      end)
      |> Enum.unzip()

    sql =
      "INSERT INTO telemetry_observations (#{Enum.map_join(columns, ", ", &Atom.to_string/1)}) " <>
        "VALUES (#{Enum.map_join(values, ", ", &SQL.literal/1)})"

    {:ok, _result} = RestClient.exec(sql, [])
  end

  defp read_two(mission_id) do
    read_back(fn ->
      case read_samples(mission_id) do
        [_, _] = samples -> {:ok, samples}
        other -> other
      end
    end)
  end

  defp read_samples(mission_id) do
    sql =
      "SELECT #{Enum.join(ObservationReader.select_columns(), ", ")} " <>
        "FROM telemetry_observations WHERE mission_id = #{SQL.literal(mission_id)}"

    {:ok, result} = RestClient.exec(sql, [])
    ObservationReader.samples_from_result(result)
  end

  # The API's provenance bytes without the reader's per-row "storage".
  defp stored(%Sample{provenance: provenance}) do
    provenance |> Map.delete("storage") |> JsonDocument.encode() |> Jason.encode!()
  end
end
