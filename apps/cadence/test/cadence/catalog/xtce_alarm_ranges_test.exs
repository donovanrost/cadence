defmodule Cadence.Catalog.XtceAlarmRangesTest do
  @moduledoc """
  2026-11-13 (director, devops): XTCE 1.2 StaticAlarmRanges default to rangeForm "outside", so a
  range is the acceptable band and the nesting puts watch innermost. An imported catalog must
  alarm out of band, not in band.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Importers.Xtce13
  alias Cadence.Catalog.MissionModel.Compiler
  alias Cadence.Catalog.Source
  alias Cadence.SemanticRuntime.{MonitoringEvaluator, MonitoringPlan, Update}

  defp rules(static_ranges) do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Bus">
      <TelemetryMetaData>
        <ParameterTypeSet>
          <FloatParameterType name="TempType">
            <FloatDataEncoding sizeInBits="32"/>
            <DefaultAlarm>
              #{static_ranges}
            </DefaultAlarm>
          </FloatParameterType>
        </ParameterTypeSet>
        <ParameterSet>
          <Parameter name="temp" parameterTypeRef="TempType"/>
        </ParameterSet>
      </TelemetryMetaData>
    </SpaceSystem>
    """

    source =
      Source.new(%{
        artifact_id: "artifact-alarm-ranges",
        organization_id: "org-alarm-ranges",
        mission_id: "mission-alarm-ranges",
        catalog_family: :combined,
        artifact_name: "bus.xml",
        format_key: "xtce_1_3",
        format_version: "1.3",
        media_type: "application/xtce+xml",
        source_artifact: xml
      })

    assert {:ok, result} = Xtce13.import(source, %{import_run_id: "import-alarm-ranges"})
    assert [layer] = result.bundle.declaration_layers
    assert {:ok, compilation} = Compiler.compile([layer])
    assert [policy] = compilation.plans.monitoring.plan["policies"]
    policy["default_rules"]
  end

  defp state(rules, value) do
    plan = MonitoringPlan.new(%{policy_id: "p", parameter_id: "temp", default_rules: rules})

    update =
      Update.new(%{
        update_id: "u-#{System.unique_integer([:positive])}",
        parameter_id: "temp",
        qualified_name: "/Bus/temp",
        value: value,
        raw_value: value,
        quality: :good,
        generation_time: ~U[2026-11-13 00:00:00Z],
        receipt_time: ~U[2026-11-13 00:00:00Z],
        producer_kind: :container,
        producer_id: "c"
      })

    {result, _state} = MonitoringEvaluator.evaluate(plan, update, %{}, %{})
    result.evaluated_state
  end

  test "outside (the default): in band is normal, each wider band out is the next level" do
    rules =
      rules("""
      <StaticAlarmRanges>
        <WatchRange minInclusive="10" maxInclusive="20"/>
        <WarningRange minInclusive="5" maxInclusive="25"/>
        <CriticalRange minInclusive="0" maxInclusive="30"/>
      </StaticAlarmRanges>
      """)

    assert state(rules, 15.0) == :normal
    assert state(rules, 20.0) == :normal
    assert state(rules, 22.0) == :watch
    assert state(rules, 4.0) == :warning
    assert state(rules, 31.0) == :critical
  end

  test "inside: a value inside a range is in that alarm" do
    rules =
      rules("""
      <StaticAlarmRanges rangeForm="inside">
        <WarningRange minInclusive="80" maxInclusive="100"/>
      </StaticAlarmRanges>
      """)

    assert state(rules, 90.0) == :warning
    assert state(rules, 50.0) == :normal
  end
end
