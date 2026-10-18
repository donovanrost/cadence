defmodule Cadence.Reads.Dashboards.ExplorationSampleSnapshotTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Reads.Dashboards.{ExplorationSampleSnapshot, ExplorationSampleValue}
  alias Cadence.TestSupport.PhysicalSampleFixtures

  test "projects stored values and exact clocks through an allowlist" do
    sample = PhysicalSampleFixtures.sample()
    assert %{status: "ready", sample: projected} = project(sample)
    assert projected.receipt_time == "2026-09-08T12:00:05.654321Z"
    assert projected.generation_time == "2026-09-08T12:00:00.123456Z"
    assert projected.raw_value == %{state: "ready", text: ~s({"adc":1234}), format: "json"}
    assert projected.engineering_value.text == "12.34"
    assert projected.quality == "suspect"
    assert projected.record.validity_state == "superseded"
    assert projected.source.source_binding_id == "binding-physical"
    refute Map.has_key?(projected, :provenance)
    refute Map.has_key?(projected.source, :organization_id)

    assert Map.keys(projected) |> Enum.sort() ==
             Enum.sort(
               ~w(point_id point_name sample_id spacecraft_id receipt_time generation_time quality raw_value engineering_value source record)a
             )
  end

  test "foreign or malformed physical identity is contained without suppressing the whole read" do
    sample = PhysicalSampleFixtures.sample()

    for invalid <- [
          %{sample | mission_id: "foreign"},
          %{sample | sample_id: "foreign"},
          %{sample | point_id: "foreign"},
          %{sample | receipt_time: nil},
          %{sample | quality_state: :unknown},
          %{sample | packet_definition_version: 9_007_199_254_740_992},
          %{sample | packet_id: String.duplicate("x", 257)},
          %{sample | provenance: %{storage: %{credentials: "never-project"}}}
        ] do
      assert project(invalid) == %{status: "unavailable", sample: nil}
    end

    for query <- [
          %{"data_source_id" => "foreign"},
          %{"source_binding_id" => "foreign"},
          %{"spacecraft_id" => "foreign"},
          %{"realm" => "simulation"},
          %{"scope_kind" => "source_endpoint", "scope_id" => "foreign"},
          %{"selected_time" => "2026-09-08T12:00:05.654320Z"}
        ] do
      assert project(sample, query) == %{status: "unavailable", sample: nil}
    end

    assert %{status: "ready"} =
             project(sample, %{"selected_time" => "2026-09-08T14:00:05.654321+02:00"})
  end

  test "no selection and finite error states never serialize private reasons" do
    assert ExplorationSampleSnapshot.build({:ok, PhysicalSampleFixtures.sample()}, %{}, nil) ==
             %{status: "not_selected", sample: nil}

    for {reason, state} <- [
          {:not_found, "not_found"},
          {:ambiguous_physical_sample, "ambiguous"},
          {:physical_sample_timeout, "timeout"},
          {:unsupported_sample_inspection, "unsupported"},
          {:unsupported_physical_sample_scope, "unsupported"},
          {{:private, "never-project"}, "unavailable"}
        ] do
      assert ExplorationSampleSnapshot.build({:error, reason}, query(), nil) ==
               %{status: state, sample: nil}
    end
  end

  test "literal values preserve integer precision, binary bytes, booleans and missing values" do
    assert ExplorationSampleValue.project(9_007_199_254_740_993).text == "9007199254740993"

    assert ExplorationSampleValue.project(<<255, 0>>) ==
             %{state: "ready", text: "ff00", format: "hex"}

    assert ExplorationSampleValue.project(false).text == "false"

    assert ExplorationSampleValue.project("<script>") ==
             %{state: "ready", text: ~s("<script>"), format: "json"}

    assert ExplorationSampleValue.project(nil) ==
             %{state: "not_recorded", text: nil, format: nil}
  end

  test "value projection bounds bytes, depth and nodes and never inspects runtime terms" do
    for value <- [
          String.duplicate("a", 4097),
          String.duplicate("\\n", 2048),
          :binary.copy(<<255>>, 2049),
          Enum.to_list(1..65),
          Map.new(1..65, &{Integer.to_string(&1), &1}),
          [[[[[1]]]]]
        ] do
      assert ExplorationSampleValue.project(value) == %{state: "limited", text: nil, format: nil}
    end

    for value <- [self(), make_ref(), fn -> :secret end, {:secret, 1}, ~U[2026-09-08 12:00:00Z]] do
      assert ExplorationSampleValue.project(value) == %{
               state: "unsupported",
               text: nil,
               format: nil
             }
    end
  end

  defp project(sample, overrides \\ %{}) do
    ExplorationSampleSnapshot.build({:ok, sample}, Map.merge(query(), overrides), %{
      mission_id: "mission-physical"
    })
  end

  defp query, do: %{"point_id" => "HK.counter", "sample_id" => "sample-physical"}
end
