defmodule Cadence.Dashboards.Sources.ConstellationHealthAlarmsTest do
  @moduledoc """
  The constellation-health frame from the runtime's alarm states (#451 T3e): each spacecraft's
  worst alarm, from the fleet summary the alarm writers keep (one statement, never every state of
  the mission). A spacecraft with no alarm is nominal when the mission's active plan monitors
  something, and `no_data` when it does not.
  """
  use Cadence.DataCase, async: false

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures, only: [source_request: 0]

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Dashboards.Sources.OperationalObservables.ConstellationHealth
  alias Cadence.MonitoringPlanFixtures
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @org "org-constellation-alarms"

  setup do
    mission = "mission-constellation-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)

    for n <- 1..3 do
      {:ok, _} =
        SpacecraftStore.persist_spacecraft(
          @org,
          Spacecraft.new(%{
            spacecraft_id: "sc-#{n}",
            organization_id: @org,
            mission_id: mission,
            display_name: "SC-#{n}",
            scid: n
          })
        )
    end

    MonitoringPlanFixtures.alarm_state!(@org, mission, "sc-1", "p1", "critical")
    MonitoringPlanFixtures.alarm_state!(@org, mission, "sc-2", "p1", "warning")
    %{mission: mission}
  end

  defp frame(mission) do
    ConstellationHealth.resolve(source_request(), @org, mission, %{}, [], [])
  end

  defp states(frame) do
    [ids, worst] = Enum.map(frame.fields, & &1.values)
    Enum.zip(ids, worst)
  end

  test "each spacecraft's worst alarm; the rest have no data while the plan monitors nothing",
       c do
    assert states(frame(c.mission)) == [{"sc-1", :red}, {"sc-2", :yellow}, {"sc-3", nil}]
  end

  test "a mission whose plan monitors something has its quiet spacecraft nominal", c do
    assert {:ok, _} =
             Cadence.Governance.persist_binding_set(
               @org,
               BindingSet.new(%{
                 organization_id: @org,
                 mission_id: c.mission,
                 binding_set_id: "basis",
                 version: 1
               })
             )

    MonitoringPlanFixtures.activate!(@org, c.mission, {"basis", 1}, [
      {"temp", "/parameters/temp", above: 10, parameter_id: "p1"}
    ])

    assert states(frame(c.mission)) == [{"sc-1", :red}, {"sc-2", :yellow}, {"sc-3", :green}]
    assert frame(c.mission).meta.counts == %{red: 1, yellow: 1, green: 1}
  end
end
