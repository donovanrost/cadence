defmodule Cadence.TestSupport.PhysicalSampleFixtures do
  @moduledoc false

  alias Cadence.Telemetry.{PhysicalSampleQuery, Sample}
  alias Cadence.Telemetry.Storage.QuestDB.ObservationReader

  def attrs(overrides \\ %{}) do
    Map.merge(
      %{
        organization_id: "org-physical",
        mission_id: "mission-physical",
        point_id: "HK.counter",
        sample_id: "sample-physical",
        data_source_id: "source-physical",
        source_binding_id: "binding-physical",
        realm: "flight"
      },
      overrides
    )
  end

  def query(overrides \\ %{}) do
    {:ok, query} = PhysicalSampleQuery.new(attrs(overrides))
    query
  end

  def sample(overrides \\ %{}) do
    struct!(
      %Sample{
        sample_id: "sample-physical",
        mission_id: "mission-physical",
        spacecraft_id: "sc-physical",
        point_id: "HK.counter",
        point_name: "Counter",
        packet_definition_id: "definition-physical",
        packet_definition_version: 1,
        packet_id: "packet-physical",
        evidence_id: "evidence-physical",
        raw_value: %{"adc" => 1234},
        engineering_value: 12.34,
        quality_state: :suspect,
        generation_time: ~U[2026-09-08 12:00:00.123456Z],
        receipt_time: ~U[2026-09-08 12:00:05.654321Z],
        provenance: %{
          "storage" => %{
            "organization_id" => "org-physical",
            "realm" => "flight",
            "data_source_id" => "source-physical",
            "binding_id" => "binding-physical",
            "source_endpoint_id" => "endpoint-physical",
            "validity_state" => "superseded"
          }
        }
      },
      overrides
    )
  end

  def questdb_result(samples) do
    columns = ["organization_id" | ObservationReader.select_columns()]

    %{
      "columns" => Enum.map(columns, &%{"name" => &1}),
      "dataset" =>
        Enum.map(samples, fn sample ->
          storage = sample.provenance["storage"]

          row =
            sample
            |> Map.from_struct()
            |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

          row = Map.merge(row, storage)

          row =
            Map.merge(row, %{
              "value_kind" => "double",
              "value_double" => sample.engineering_value,
              "raw_value_text" => Jason.encode!(sample.raw_value),
              "quality_state" => Atom.to_string(sample.quality_state),
              "generation_time" => iso(sample.generation_time),
              "receipt_time" => iso(sample.receipt_time),
              "provenance_json" => "{}"
            })

          Enum.map(columns, &Map.get(row, &1))
        end)
    }
  end

  defp iso(nil), do: nil
  defp iso(value), do: DateTime.to_iso8601(value)
end
