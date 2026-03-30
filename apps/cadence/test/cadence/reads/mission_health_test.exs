defmodule Cadence.Reads.MissionHealthTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.Telemetry.PacketDefinition

  setup do
    organization_id = "org-mission-health"
    mission_id = "mission-alpha"

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "builds a dashboard-oriented mission health summary from latest limit states", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    binding_set = persist_binding_set_fixture(organization_id, mission_id)
    persist_limit_definitions_fixture()

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 25, 50, 1_700_001_000),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 15, 250, 1_700_001_010, "sc-001"),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(3, 5, 120, 1_700_001_020, "sc-002"),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, limit_run} = Cadence.evaluate_telemetry_limits("mission-alpha")
    assert limit_run.status == :completed

    summary = Cadence.mission_health_summary(organization_id, mission_id, [])

    assert summary.total_points == 6
    assert summary.violating_points == 4
    assert summary.normalized_state_counts == %{red: 2, yellow: 2, green: 2, blue: 0}
    assert summary.worst_normalized_state == :red

    assert DateTime.compare(summary.updated_at, DateTime.from_unix!(1_700_001_020, :second)) ==
             :eq

    assert summary.point_buckets.red |> Enum.map(& &1.point_id) == ["HK.counter", "HK.voltage"]
    assert summary.point_buckets.yellow |> Enum.map(& &1.point_id) == ["HK.counter", "HK.voltage"]
    assert summary.point_buckets.green |> Enum.map(& &1.point_id) == ["HK.voltage", "HK.counter"]
    assert summary.point_buckets.blue == []

    assert Enum.map(summary.scope_summaries, &scope_overview/1) == [
             {"mission:mission-alpha", :mission, nil, :red, 2, 1},
             {"spacecraft:sc-001", :spacecraft, "sc-001", :red, 2, 2},
             {"spacecraft:sc-002", :spacecraft, "sc-002", :yellow, 2, 1}
           ]

    mission_scope = Enum.at(summary.scope_summaries, 0)
    assert mission_scope.normalized_state_counts == %{red: 1, yellow: 0, green: 1, blue: 0}
    assert mission_scope.point_buckets.red |> Enum.map(& &1.point_id) == ["HK.counter"]
    assert mission_scope.point_buckets.green |> Enum.map(& &1.point_id) == ["HK.voltage"]

    spacecraft_scope = Enum.at(summary.scope_summaries, 1)
    assert spacecraft_scope.normalized_state_counts == %{red: 1, yellow: 1, green: 0, blue: 0}
    assert spacecraft_scope.point_buckets.red |> Enum.map(& &1.point_id) == ["HK.voltage"]
    assert spacecraft_scope.point_buckets.yellow |> Enum.map(& &1.point_id) == ["HK.counter"]
  end

  test "filters the health summary to one spacecraft scope", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    binding_set = persist_binding_set_fixture(organization_id, mission_id)
    persist_limit_definitions_fixture()

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 25, 50, 1_700_001_000),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 15, 250, 1_700_001_010, "sc-001"),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, limit_run} = Cadence.evaluate_telemetry_limits("mission-alpha")
    assert limit_run.status == :completed

    summary =
      Cadence.mission_health_summary(organization_id, mission_id, spacecraft_id: "sc-001")

    assert summary.total_points == 2
    assert summary.violating_points == 2
    assert summary.normalized_state_counts == %{red: 1, yellow: 1, green: 0, blue: 0}
    assert summary.worst_normalized_state == :red

    assert DateTime.compare(summary.updated_at, DateTime.from_unix!(1_700_001_010, :second)) ==
             :eq

    assert summary.point_buckets.red |> Enum.map(& &1.point_id) == ["HK.voltage"]
    assert summary.point_buckets.yellow |> Enum.map(& &1.point_id) == ["HK.counter"]

    assert Enum.map(summary.scope_summaries, &scope_overview/1) == [
             {"spacecraft:sc-001", :spacecraft, "sc-001", :red, 2, 2}
           ]
  end

  defp scope_overview(scope_summary) do
    {
      scope_summary.scope_id,
      scope_summary.scope_kind,
      scope_summary.spacecraft_id,
      scope_summary.worst_normalized_state,
      scope_summary.total_points,
      scope_summary.violating_points
    }
  end

  defp persist_binding_set_fixture(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-mission-health",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint},
          %{name: "voltage", offset_bits: 16, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: mission_id <> "-mission-health",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted_binding_set} =
             Cadence.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id
    persisted_binding_set
  end

  defp persist_limit_definitions_fixture do
    counter_limit_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "hk-counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    voltage_limit_definition =
      Definition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "hk-voltage-limits",
        point_id: "HK.voltage",
        thresholds: %{"yellow_high" => 100, "red_high" => 200}
      })

    assert {:ok, ^counter_limit_definition} =
             Cadence.persist_limit_definition(counter_limit_definition)

    assert {:ok, ^voltage_limit_definition} =
             Cadence.persist_limit_definition(voltage_limit_definition)

    :ok
  end

  defp raw_evidence_fixture(sequence_count, counter_value, voltage_value, receipt_unix) do
    raw_evidence_fixture(sequence_count, counter_value, voltage_value, receipt_unix, nil)
  end

  defp raw_evidence_fixture(
         sequence_count,
         counter_value,
         voltage_value,
         receipt_unix,
         spacecraft_id
       ) do
    RawEvidence.new(%{
      mission_id: "mission-alpha",
      spacecraft_id: spacecraft_id,
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(42, sequence_count, <<counter_value::16, voltage_value::16>>)
    })
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
