defmodule Cadence.Catalog.TelemetryBindingTest do
  @moduledoc """
  Pins the telemetry binding id format (DECISIONS #103): stored observations no longer carry their
  binding_rule_id when it equals `Catalog.binding_rule_id/3`, and readers rebuild it from the
  parts. If either test fails, stored rows would read back with a different binding id.
  """
  use Cadence.DataCase, async: true

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Catalog
  alias Cadence.Catalog.TelemetryBinding
  alias Cadence.SourceEndpoints

  @organization_id "org-binding-id"
  @mission_id "mission-binding-id"

  describe "binding_rule_id/3" do
    test "the format, literally" do
      assert Catalog.binding_rule_id("mmr_1", "sc_7", "packet_def_42") ==
               "mission_model_telemetry:mmr_1:spacecraft_runtime:sc_7:packet_def_42:rule"
    end

    test "is the rule id of the capability on the spacecraft's managed source endpoint" do
      endpoint = SourceEndpoints.managed_source_endpoint_id("sc_7")

      assert Catalog.binding_rule_id("mmr_1", "sc_7", "packet_def_42") ==
               "mmr_1"
               |> TelemetryBinding.capability_instance_id(endpoint, "packet_def_42")
               |> TelemetryBinding.rule_id()
    end

    test "refuses a missing part rather than building a wrong id" do
      for {revision, spacecraft, producer} <- [
            {nil, "sc", "p"},
            {"r", nil, "p"},
            {"r", "sc", nil}
          ] do
        assert_raise FunctionClauseError, fn ->
          Catalog.binding_rule_id(revision, spacecraft, producer)
        end
      end
    end
  end

  test "decom compiles exactly that id for each packet of a configured spacecraft" do
    spacecraft = TelemetryDecomFixtures.setup_spacecraft!(@organization_id, @mission_id)

    revision =
      TelemetryDecomFixtures.persist_imported_revision!(@organization_id, @mission_id)

    # No endpoint named: decom provisions the spacecraft's managed one.
    {:ok, config} =
      TelemetryDecom.configure(@organization_id, @mission_id, spacecraft.spacecraft_id,
        catalog_revision_id: revision.catalog_revision_id,
        handled_apids: [42]
      )

    assert {:ok, %{rules: [_ | _] = rules, capability_instances: instances}} =
             TelemetryDecom.compile_mission_contribution(@organization_id, @mission_id, [config])

    # The packet each rule decodes, from the compiled capability itself (not parsed from its id).
    packets =
      Map.new(instances, &{&1.capability_instance_id, &1.runtime_configuration})

    for rule <- rules do
      packet = Map.fetch!(packets, rule.capability_instance_id)

      assert rule.binding_rule_id ==
               Catalog.binding_rule_id(
                 revision.mission_model_revision_id,
                 spacecraft.spacecraft_id,
                 packet.packet_definition_id
               )
    end
  end
end
