defmodule Cadence.TargetsIntegrationTest do
  @moduledoc """
  Integration tests for Targets persistence constraints.
  """

  use Cadence.DataCase, async: true

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.MissionDatabaseFixtures

  alias Cadence.Targets

  describe "create_target/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      definition_set = definition_set_fixture(organization: org, mission: mission)

      %{mission: mission, definition_set: definition_set}
    end

    test "enforces unique identifier per mission", %{mission: mission, definition_set: ds} do
      attrs = %{
        mission_id: mission.id,
        definition_set_id: ds.id,
        name: "Satellite 1",
        identifier: "SAT-001",
        type: :spacecraft
      }

      assert {:ok, _} = Targets.create_target(attrs)
      assert {:error, errors} = Targets.create_target(attrs)
      assert is_map(errors)
    end
  end
end
