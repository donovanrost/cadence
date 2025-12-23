defmodule Cadence.Application.Missions.MembershipOperations do
  @moduledoc """
  Use case module for mission membership operations.

  Provides operations for managing mission memberships including
  creating, updating roles, and removing members.

  ## Usage

      # Add a member
      {:ok, membership} = MembershipOperations.add_member(mission_id, user_id, :operator)

      # Change role
      {:ok, membership} = MembershipOperations.change_role(membership_id, :engineer)

      # Remove member
      :ok = MembershipOperations.remove_member(membership_id)
  """

  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Domain.Missions.Entities.MissionMembership
  alias Cadence.Domain.Missions.ValueObjects.MembershipRole
  alias Cadence.Ports.Repository.Missions.MissionsRepository

  @type membership_id :: String.t()
  @type mission_id :: String.t()
  @type user_id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    MissionsRepository.impl()
  end

  @doc """
  Adds a member to a mission.

  ## Arguments

  - `mission_id` - ID of the mission
  - `user_id` - ID of the user to add
  - `role` - Optional role (default: :viewer)

  ## Examples

      {:ok, membership} = MembershipOperations.add_member(mission_id, user_id, :operator)
  """
  @spec add_member(mission_id(), user_id(), MembershipRole.t() | nil) ::
          {:ok, MissionMembership.t()} | {:error, term()}
  def add_member(mission_id, user_id, role \\ nil) do
    with {:ok, _mission} <- MissionQueries.find(mission_id),
         {:ok, membership} <-
           MissionMembership.new(%{
             mission_id: mission_id,
             user_id: user_id,
             role: role
           }),
         {:ok, saved} <- repo().save_membership(membership) do
      {:ok, saved}
    end
  end

  @doc """
  Changes the role of an existing membership.

  ## Examples

      {:ok, membership} = MembershipOperations.change_role(membership_id, :engineer)
  """
  @spec change_role(membership_id(), MembershipRole.t()) ::
          {:ok, MissionMembership.t()} | {:error, term()}
  def change_role(membership_id, new_role) do
    with {:ok, membership} <- repo().find_membership(membership_id),
         {:ok, updated} <- MissionMembership.update_role(membership, new_role),
         {:ok, saved} <- repo().save_membership(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Removes a member from a mission.
  """
  @spec remove_member(membership_id()) :: :ok | {:error, term()}
  def remove_member(membership_id) do
    case repo().delete_membership(membership_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds a membership by ID.
  """
  @spec find(membership_id()) :: {:ok, MissionMembership.t()} | {:error, :not_found}
  def find(membership_id), do: repo().find_membership(membership_id)

  @doc """
  Lists all members of a mission.

  ## Options

  - `:role` - Filter by role
  - `:preload` - Associations to preload (e.g., [:user])
  """
  @spec list_members(mission_id(), keyword()) :: [MissionMembership.t()]
  def list_members(mission_id, opts \\ []), do: repo().list_memberships(mission_id, opts)

  @doc """
  Checks if a user is a member of a mission.
  """
  @spec member?(user_id(), mission_id()) :: boolean()
  def member?(user_id, mission_id) do
    MissionQueries.member?(user_id, mission_id)
  end

  @doc """
  Gets the count of members in a mission.
  """
  @spec count_members(mission_id()) :: non_neg_integer()
  def count_members(mission_id) do
    mission_id
    |> list_members()
    |> length()
  end
end
