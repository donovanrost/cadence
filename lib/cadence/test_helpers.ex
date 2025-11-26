defmodule Cadence.TestHelpers do
  @moduledoc """
  Helper functions for testing and development.

  These functions make it easy to set up test data without building full UI.
  """

  alias Cadence.{Targets, Missions}

  @doc """
  Creates standard test targets for a mission.

  Creates 3 spacecraft targets (SAT-1, SAT-2, SAT-3) that work with the packet simulator.

  ## Examples

      # In IEx:
      mission = Cadence.Missions.get_mission!("mission-id-here")
      Cadence.TestHelpers.create_test_targets(mission)

      # Returns:
      {:ok, [target1, target2, target3]}
  """
  def create_test_targets(mission) when is_binary(mission) do
    Missions.get_mission!(mission)
    |> create_test_targets()
  end

  def create_test_targets(%Missions.Mission{} = mission) do
    target_configs = [
      %{identifier: "SAT-1", name: "Satellite 1"},
      %{identifier: "SAT-2", name: "Satellite 2"},
      %{identifier: "SAT-3", name: "Satellite 3"}
    ]

    results = Enum.map(target_configs, fn config ->
      Targets.create_target(%{
        mission_id: mission.id,
        name: config.name,
        identifier: config.identifier,
        type: "spacecraft",
        status: "online"
      })
    end)

    # Check if all succeeded
    if Enum.all?(results, &match?({:ok, _}, &1)) do
      targets = Enum.map(results, fn {:ok, target} -> target end)
      IO.puts("✅ Created 3 test targets: SAT-1, SAT-2, SAT-3")
      {:ok, targets}
    else
      errors = Enum.filter(results, &match?({:error, _}, &1))
      IO.puts("❌ Failed to create some targets")
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
    mission = if is_binary(mission), do: Missions.get_mission!(mission), else: mission

    name = Keyword.get(opts, :name, identifier)
    type = Keyword.get(opts, :type, "spacecraft")
    status = Keyword.get(opts, :status, "online")

    case Targets.create_target(%{
      mission_id: mission.id,
      name: name,
      identifier: identifier,
      type: type,
      status: status
    }) do
      {:ok, target} ->
        IO.puts("✅ Created target: #{identifier}")
        {:ok, target}

      {:error, changeset} ->
        IO.puts("❌ Failed to create target: #{identifier}")
        IO.inspect(changeset.errors)
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
    {:ok, org} = Organizations.create_organization(%{
      name: org_name,
      slug: "test-org-#{System.unique_integer([:positive])}",
      status: "active",
      subscription_tier: "pro"
    })

    # Create user
    {:ok, user} = Accounts.register_user(%{
      email: "test-#{System.unique_integer([:positive])}@example.com",
      organization_id: org.id,
      role: "admin"
    })

    # Create mission
    {:ok, mission} = Missions.create_mission(%{
      organization_id: org.id,
      name: mission_name,
      slug: "test-mission-#{System.unique_integer([:positive])}",
      description: "Test mission for development",
      status: "active",
      creator_user_id: user.id
    })

    # Create targets
    {:ok, targets} = create_test_targets(mission)

    IO.puts("\n✅ Full test setup complete!")
    IO.puts("   Organization: #{org.name} (#{org.id})")
    IO.puts("   User: #{user.email}")
    IO.puts("   Mission: #{mission.name} (#{mission.id})")
    IO.puts("   Targets: #{length(targets)} created")
    IO.puts("\n📊 View at: http://localhost:4000/missions/#{mission.id}")

    %{
      org: org,
      user: user,
      mission: mission,
      targets: targets
    }
  end
end
