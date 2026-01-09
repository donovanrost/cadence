defmodule Cadence.TestHelpers do
  @moduledoc """
  Helper functions for testing and development.

  These functions make it easy to set up test data without building full UI.
  """
  require Logger

  alias Cadence.Domain.Missions.Entities.Mission, as: DomainMission
  alias Cadence.MissionDatabase.{Database, DefinitionSet}
  alias Cadence.{Missions, Targets}
  alias Cadence.Repo

  @doc """
  Creates a test database and definition set for a mission.

  Returns {:ok, definition_set} that can be used when creating targets.
  """
  def create_test_definition_set(mission) when is_binary(mission) do
    Missions.get_mission!(mission)
    |> create_test_definition_set()
  end

  def create_test_definition_set(%DomainMission{} = mission) do
    {:ok, database} =
      %Database{}
      |> Database.changeset(%{
        mission_id: mission.id,
        name: "Test Database",
        slug: "test-database-#{System.unique_integer([:positive])}",
        description: "Test database for development"
      })
      |> Repo.insert()

    {:ok, definition_set} =
      %DefinitionSet{}
      |> DefinitionSet.changeset(%{
        organization_id: mission.organization_id,
        database_id: database.id,
        version: "1.0.0",
        source_format: :yaml,
        published_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, definition_set}
  end

  def create_test_definition_set(%Missions.Mission{} = mission) do
    # Ensure mission has organization_id loaded
    mission =
      if Ecto.assoc_loaded?(mission.organization) do
        mission
      else
        Repo.preload(mission, :organization)
      end

    # Create a test database for the mission
    {:ok, database} =
      %Database{}
      |> Database.changeset(%{
        mission_id: mission.id,
        name: "Test Database",
        slug: "test-database-#{System.unique_integer([:positive])}",
        description: "Test database for development"
      })
      |> Repo.insert()

    # Create a definition set for the database
    {:ok, definition_set} =
      %DefinitionSet{}
      |> DefinitionSet.changeset(%{
        organization_id: mission.organization_id,
        database_id: database.id,
        version: "1.0.0",
        source_format: :yaml,
        published_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, definition_set}
  end

  @doc """
  Creates standard test targets for a mission.

  Creates 3 spacecraft targets (SAT-1, SAT-2, SAT-3) that work with the packet simulator.
  Also creates required Database and DefinitionSet if needed.

  ## Examples

      # In IEx:
      mission = Cadence.Missions.get_mission!("mission-id-here")
      Cadence.TestHelpers.create_test_targets(mission)

      # Returns:
      {:ok, [target1, target2, target3]}
  """
  def create_test_targets(mission) when is_binary(mission) do
    # Test helper - use unscoped for convenience
    Missions.get_mission!(mission)
    |> create_test_targets()
  end

  def create_test_targets(%DomainMission{} = mission) do
    {:ok, definition_set} = create_test_definition_set(mission)

    target_configs = [
      %{identifier: "SAT-1", name: "Satellite 1"},
      %{identifier: "SAT-2", name: "Satellite 2"},
      %{identifier: "SAT-3", name: "Satellite 3"}
    ]

    results =
      Enum.map(target_configs, fn config ->
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: definition_set.id,
          name: config.name,
          identifier: config.identifier,
          type: "spacecraft",
          status: "online"
        })
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      targets = Enum.map(results, fn {:ok, target} -> target end)
      log_test_output(:info, "✅ Created 3 test targets: SAT-1, SAT-2, SAT-3")
      {:ok, targets}
    else
      errors = Enum.filter(results, &match?({:error, _}, &1))
      log_test_output(:error, "❌ Failed to create some targets")
      {:error, errors}
    end
  end

  def create_test_targets(%Missions.Mission{} = mission) do
    # First, create a definition set for this mission
    {:ok, definition_set} = create_test_definition_set(mission)

    target_configs = [
      %{identifier: "SAT-1", name: "Satellite 1"},
      %{identifier: "SAT-2", name: "Satellite 2"},
      %{identifier: "SAT-3", name: "Satellite 3"}
    ]

    results =
      Enum.map(target_configs, fn config ->
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: definition_set.id,
          name: config.name,
          identifier: config.identifier,
          type: "spacecraft",
          status: "online"
        })
      end)

    # Check if all succeeded
    if Enum.all?(results, &match?({:ok, _}, &1)) do
      targets = Enum.map(results, fn {:ok, target} -> target end)
      log_test_output(:info, "✅ Created 3 test targets: SAT-1, SAT-2, SAT-3")
      {:ok, targets}
    else
      errors = Enum.filter(results, &match?({:error, _}, &1))
      log_test_output(:error, "❌ Failed to create some targets")
      {:error, errors}
    end
  end

  @doc """
  Creates a custom target for a mission.

  ## Examples

      Cadence.TestHelpers.create_target(mission, "GROUND-STATION-1",
        name: "Ground Station Alpha",
        type: "ground_station"
      )
  """
  def create_target(mission, identifier, opts \\ []) when is_binary(identifier) do
    # Test helper - use unscoped for convenience
    mission = if is_binary(mission), do: Missions.get_mission!(mission), else: mission

    name = Keyword.get(opts, :name, identifier)
    type = Keyword.get(opts, :type, "spacecraft")
    status = Keyword.get(opts, :status, "online")

    # Get or create a definition_set
    definition_set_id =
      case Keyword.get(opts, :definition_set_id) do
        nil ->
          {:ok, ds} = create_test_definition_set(mission)
          ds.id

        id ->
          id
      end

    case Targets.create_target(%{
           mission_id: mission.id,
           definition_set_id: definition_set_id,
           name: name,
           identifier: identifier,
           type: type,
           status: status
         }) do
      {:ok, target} ->
        log_test_output(:info, "✅ Created target: #{identifier}")
        {:ok, target}

      {:error, changeset} ->
        require Logger

        Logger.error(
          "Failed to create target: #{identifier}, errors: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  @doc """
  Complete test setup: creates org, user, mission, and targets.

  Returns a map with all the created entities.

  ## Examples

      setup = Cadence.TestHelpers.full_test_setup()
      # => %{org: ..., user: ..., mission: ..., targets: [...]}
  """
  def full_test_setup(opts \\ []) do
    alias Cadence.{Accounts, Organizations}

    org_name = Keyword.get(opts, :org_name, "Test Org #{System.unique_integer([:positive])}")
    mission_name = Keyword.get(opts, :mission_name, "Test Mission")

    # Create organization
    {:ok, org} =
      Organizations.create_organization(%{
        name: org_name,
        slug: "test-org-#{Ecto.UUID.generate()}",
        status: "active",
        subscription_tier: "pro"
      })

    # Create user
    {:ok, user} =
      Accounts.register_user(%{
        email: "test-#{Ecto.UUID.generate()}@example.com",
        organization_id: org.id,
        role: "admin"
      })

    # Create mission
    {:ok, mission} =
      Missions.create_mission(org.id, %{
        name: mission_name,
        slug: "test-mission-#{Ecto.UUID.generate()}",
        description: "Test mission for development",
        status: "active",
        creator_user_id: user.id
      })

    # Create targets
    {:ok, targets} = create_test_targets(mission)

    log_test_output(:info, "\n✅ Full test setup complete!")
    log_test_output(:info, "   Organization: #{org.name} (#{org.id})")
    log_test_output(:info, "   User: #{user.email}")
    log_test_output(:info, "   Mission: #{mission.name} (#{mission.id})")
    log_test_output(:info, "   Targets: #{length(targets)} created")
    log_test_output(:info, "\n📊 View at: http://localhost:4000/missions/#{mission.id}")

    %{
      org: org,
      user: user,
      mission: mission,
      targets: targets
    }
  end

  defp log_test_output(level, message) do
    if verbose_test_output?() do
      Logger.log(level, message)
    end
  end

  defp verbose_test_output? do
    case System.get_env("CADENCE_TEST_VERBOSE") do
      "1" -> true
      "true" -> true
      "TRUE" -> true
      _ -> false
    end
  end
end
