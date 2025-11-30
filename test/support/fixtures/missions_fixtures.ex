defmodule Cadence.MissionsFixtures do
  @moduledoc """
  Test helpers for creating mission entities.
  """

  alias Cadence.Missions.Mission
  alias Cadence.Repo

  import Cadence.OrganizationsFixtures

  def unique_mission_slug, do: "mission-#{System.unique_integer([:positive])}"

  def mission_fixture(attrs \\ %{}) do
    # Ensure attrs is a map
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    org = attrs[:organization] || organization_fixture()

    attrs =
      attrs
      |> Map.delete(:organization)
      |> Enum.into(%{
        organization_id: org.id,
        name: "Test Mission",
        slug: unique_mission_slug(),
        status: "active",
        phase: "operational"
      })

    %Mission{}
    |> Mission.changeset(attrs)
    |> Repo.insert!()
  end
end
