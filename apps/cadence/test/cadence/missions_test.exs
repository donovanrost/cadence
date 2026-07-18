defmodule Cadence.MissionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Missions

  test "resolves organization ownership for a persisted mission" do
    persist_mission_scope("org-missions-owner", "mission-missions-owner")

    assert Missions.organization_id_for_mission("mission-missions-owner") ==
             "org-missions-owner"

    assert Missions.organization_id_for_mission("mission-missing") == nil
  end
end
