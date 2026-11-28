defmodule Cadence.MissionModels.PlanIdentityTest do
  @moduledoc """
  A plan's id names its content, not its revision (#443): two revisions that leave a target's plan
  alone store the same plan id, each under its own revision, and each plan still says which
  revision it was compiled under.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.MissionModels

  @org "org-plan-identity"

  setup do
    mission = "mission-plan-identity-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  test "revisions with unchanged plans store the same plan ids, one row each", %{mission: mission} do
    {:ok, first} = MissionModels.compile_layers([layer(mission, "v1", [])])
    {:ok, second} = MissionModels.compile_layers([layer(mission, "v2", ["/parameters/extra"])])

    refute first.revision.revision_id == second.revision.revision_id

    assert {:ok, plans_1} =
             MissionModels.fetch_runtime_plans(@org, mission, first.revision.revision_id)

    assert {:ok, plans_2} =
             MissionModels.fetch_runtime_plans(@org, mission, second.revision.revision_id)

    for target <- [:telemetry, :algorithm, :monitoring, :command] do
      assert plans_1[target].plan_id == plans_2[target].plan_id
      assert plans_1[target].content_sha256 == plans_2[target].content_sha256
      assert plans_1[target].mission_model_revision_id == first.revision.revision_id
      assert plans_2[target].mission_model_revision_id == second.revision.revision_id
    end
  end

  test "recompiling a revision stores nothing twice", %{mission: mission} do
    layer = layer(mission, "again", [])
    {:ok, first} = MissionModels.compile_layers([layer])
    {:ok, again} = MissionModels.compile_layers([layer])

    assert first.revision.revision_id == again.revision.revision_id

    assert {:ok, %{telemetry: _}} =
             MissionModels.fetch_runtime_plans(@org, mission, again.revision.revision_id)
  end

  defp layer(mission, name, parameters) do
    Layer.new(%{
      organization_id: @org,
      mission_id: mission,
      name: name,
      declarations:
        [%{kind: :space_system, qualified_name: "/"}] ++
          for(path <- parameters, do: %{kind: :parameter, qualified_name: path})
    })
  end
end
