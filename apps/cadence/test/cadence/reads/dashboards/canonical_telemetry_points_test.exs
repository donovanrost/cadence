defmodule Cadence.Reads.Dashboards.CanonicalTelemetryPointsTest do
  @moduledoc """
  #451 T4d: the canonical point choices (the dashboards' observable picker) list the active
  revision's derived parameters from the operator point catalog (#1124), by semantic id and
  qualified name with their unit, not the retired governed derived definitions.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.DerivedPointFixtures, as: Fixtures
  alias Cadence.Reads.Dashboards.CanonicalTelemetryPoints

  @org "org-canonical-points"

  setup do
    mission = "mission-canonical-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission, model: Fixtures.activate!(@org, mission)}
  end

  test "a derived parameter is a choice, by its semantic id, labelled by its qualified name", c do
    assert {:ok, page} = search(c.mission, "")
    derived = Enum.find(page.options, &(&1.value == c.model.derived_id))

    assert %{label: label, description: description} = derived
    assert label == Fixtures.derived_name()
    assert description =~ "Derived telemetry"
    assert description =~ "Unit: V"
  end

  test "a query matches a derived point by its qualified name", c do
    query = Fixtures.derived_name() |> String.split("/") |> List.last()

    assert {:ok, page} = search(c.mission, query)
    assert Enum.any?(page.options, &(&1.value == c.model.derived_id))
  end

  defp search(mission, query) do
    CanonicalTelemetryPoints.search(%Scope{organization_id: @org}, mission, query, 50)
  end
end
