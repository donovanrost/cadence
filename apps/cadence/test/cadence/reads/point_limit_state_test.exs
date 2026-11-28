defmodule Cadence.Reads.PointLimitStateTest do
  @moduledoc """
  A spacecraft's limit state per point from the runtime's alarm states and the compiled plan
  (#451 T3c): the worst level over a parameter's policies; `:nominal` for a parameter the plan
  monitors there that never left normal; nothing for one no plan monitors; states that raise and
  clear nothing (`disabled`, `unknown`) say nothing.
  """
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.MonitoringPlanFixtures, as: Fixtures
  alias Cadence.Reads.PointLimitState
  alias Cadence.SemanticObservations

  @org "org-point-limit-state"

  setup do
    mission = "mission-point-limit-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  defp catalog(parameters),
    do: for(parameter <- parameters, do: %{point_id: "pt-#{parameter}", parameter_id: parameter})

  defp state!(c, craft, parameter, state, policy) do
    Fixtures.alarm_state!(@org, c.mission, craft, parameter, state, policy_id: policy)
  end

  test "levels are the worst over a parameter's policies; text states map through AlarmLevel",
       c do
    state!(c, "sc-1", "p1", "warning", "pol-a")
    state!(c, "sc-1", "p1", "severe", "pol-b")
    state!(c, "sc-1", "p2", "watch", "pol-a")
    state!(c, "sc-1", "p3", "normal", "pol-a")
    state!(c, "sc-1", "p4", "disabled", "pol-a")
    state!(c, "sc-1", "p5", "unknown", "pol-a")
    state!(c, "sc-2", "p1", "normal", "pol-a")

    assert SemanticObservations.levels_for_spacecraft(@org, c.mission, "sc-1") ==
             %{"p1" => :critical, "p2" => :caution, "p3" => :nominal}

    assert SemanticObservations.levels_for_spacecraft(@org, c.mission, "sc-2") ==
             %{"p1" => :nominal}

    assert SemanticObservations.levels_for_spacecraft(@org, c.mission, "sc-3") == %{}
  end

  test "a point with no state is nominal when the plan monitors it there, and absent when not",
       c do
    bindings =
      BindingSet.new(%{
        organization_id: @org,
        mission_id: c.mission,
        binding_set_id: "basis",
        version: 1
      })

    assert {:ok, _stored} = Cadence.Governance.persist_binding_set(@org, bindings)

    Fixtures.activate!(@org, c.mission, {"basis", 1}, [
      {"temp", "/parameters/temp", above: 10, parameter_id: "p-temp"},
      {"volts", "/parameters/volts", above: 5, parameter_id: "p-volts"}
    ])

    state!(c, "sc-1", "p-volts", "critical", "pol-v")
    points = catalog(["p-temp", "p-volts", "p-other"])

    # p-temp is monitored and never left normal; p-volts alarms; p-other is nobody's.
    assert PointLimitState.load(@org, c.mission, "sc-1", points) ==
             %{"pt-p-temp" => :nominal, "pt-p-volts" => :critical}
  end

  test "only the asked points, and a point the catalog does not map is its own parameter", c do
    state!(c, "sc-1", "pt-bare", "warning", "pol-a")
    state!(c, "sc-1", "p1", "critical", "pol-a")

    points = [%{point_id: "pt-bare", parameter_id: nil}, %{point_id: "pt-1", parameter_id: "p1"}]

    assert PointLimitState.load(@org, c.mission, "sc-1", points) ==
             %{"pt-bare" => :caution, "pt-1" => :critical}

    assert PointLimitState.load(@org, c.mission, "sc-1", points, ["pt-1"]) ==
             %{"pt-1" => :critical}
  end
end
