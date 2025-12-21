defmodule Cadence.TargetsFixtures do
  @moduledoc """
  Test helpers for creating Target entities.
  """

  alias Cadence.Repo
  alias Cadence.Targets.Target

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.MissionDatabaseFixtures

  # ============================================================================
  # Target
  # ============================================================================

  @doc """
  Generate a unique target identifier.
  """
  def unique_target_identifier, do: "SAT-#{System.unique_integer([:positive])}"

  @doc """
  Creates a target fixture.

  ## Options

  - `:organization` - Organization to use (will create one if not provided)
  - `:mission` - Mission to use (will create one if not provided)
  - `:definition_set` - DefinitionSet to use (will create one if not provided)
  - `:name` - Target name (default: "Test Target")
  - `:identifier` - Target identifier (default: unique identifier)
  - `:type` - Target type (default: "spacecraft")
  - `:status` - Target status (default: "offline")

  ## Examples

      # Create a basic target
      target = target_fixture()

      # Create a target for a specific mission
      target = target_fixture(mission: mission)

      # Create an online spacecraft target
      target = target_fixture(type: "spacecraft", status: "online")
  """
  def target_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    # Get or create org, mission, and definition_set
    org = attrs[:organization] || organization_fixture()
    mission = attrs[:mission] || mission_fixture(organization: org)

    definition_set =
      attrs[:definition_set] ||
        definition_set_fixture(organization: org, mission: mission)

    attrs =
      attrs
      |> Map.drop([:organization, :mission, :definition_set])
      |> Enum.into(%{
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "Test Target",
        identifier: unique_target_identifier(),
        type: "spacecraft",
        status: "offline"
      })

    %Target{}
    |> Target.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a spacecraft target fixture.
  """
  def spacecraft_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    target_fixture(Map.merge(attrs, %{type: "spacecraft"}))
  end

  @doc """
  Creates a ground station target fixture.
  """
  def ground_station_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    target_fixture(Map.merge(attrs, %{type: "ground_station"}))
  end

  @doc """
  Creates an online target fixture.
  """
  def online_target_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    target_fixture(Map.merge(attrs, %{status: "online"}))
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp ensure_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp ensure_map(attrs) when is_map(attrs), do: attrs
end
