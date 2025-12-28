defmodule Cadence.Application.Organizations.QuotaService do
  @moduledoc """
  Service module for checking organization quotas.

  This module provides quota checking functionality that can be used
  by other domain contexts (e.g., Missions, Targets) to enforce limits.

  ## Usage

      # Check if org can create a mission
      :ok = QuotaService.check_mission_quota(org_id)

      # Check if mission can add a target
      :ok = QuotaService.check_target_quota(org_id, mission_id)

      # Check if org can add a user
      :ok = QuotaService.check_user_quota(org_id)
  """

  alias Cadence.Application.Organizations.OrganizationQueries
  alias Cadence.Domain.Organizations.Entities.Organization

  @type org_id :: String.t()
  @type mission_id :: String.t()

  @doc """
  Checks if an organization can create a new mission.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.

  ## Examples

      :ok = QuotaService.check_mission_quota(org_id)
      {:error, :quota_exceeded} = QuotaService.check_mission_quota(full_org_id)
  """
  @spec check_mission_quota(org_id()) :: :ok | {:error, :quota_exceeded | :not_found}
  def check_mission_quota(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id) do
      mission_count = OrganizationQueries.count_missions(org_id)
      Organization.check_mission_quota(org, mission_count)
    end
  end

  @doc """
  Checks if a mission can add a new target.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.

  ## Examples

      :ok = QuotaService.check_target_quota(org_id, mission_id)
  """
  @spec check_target_quota(org_id(), mission_id()) :: :ok | {:error, :quota_exceeded | :not_found}
  def check_target_quota(org_id, mission_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id) do
      target_count = OrganizationQueries.count_mission_targets(mission_id)
      Organization.check_target_quota(org, target_count)
    end
  end

  @doc """
  Checks if an organization can add a new user.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.

  ## Examples

      :ok = QuotaService.check_user_quota(org_id)
  """
  @spec check_user_quota(org_id()) :: :ok | {:error, :quota_exceeded | :not_found}
  def check_user_quota(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id) do
      user_count = OrganizationQueries.count_users(org_id)
      Organization.check_user_quota(org, user_count)
    end
  end

  @doc """
  Returns the remaining quota capacity for an organization.

  ## Returns

  A map containing remaining capacity for each resource type.

  ## Examples

      %{
        missions: 3,
        users: 5,
        storage_gb: 50
      } = QuotaService.get_remaining_quota(org_id)
  """
  @spec get_remaining_quota(org_id()) :: {:ok, map()} | {:error, :not_found}
  def get_remaining_quota(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id) do
      mission_count = OrganizationQueries.count_missions(org_id)
      user_count = OrganizationQueries.count_users(org_id)

      {:ok,
       %{
         missions: max(0, org.quotas.max_missions - mission_count),
         users: max(0, org.quotas.max_users - user_count),
         targets_per_mission: org.quotas.max_targets_per_mission,
         storage_gb: org.quotas.storage_quota_gb
       }}
    end
  end

  @doc """
  Returns quota usage as percentages.

  ## Examples

      %{
        missions: 80.0,
        users: 50.0
      } = QuotaService.get_quota_usage(org_id)
  """
  @spec get_quota_usage(org_id()) :: {:ok, map()} | {:error, :not_found}
  def get_quota_usage(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id) do
      mission_count = OrganizationQueries.count_missions(org_id)
      user_count = OrganizationQueries.count_users(org_id)

      {:ok,
       %{
         missions: percentage(mission_count, org.quotas.max_missions),
         users: percentage(user_count, org.quotas.max_users)
       }}
    end
  end

  @doc """
  Checks if an organization is at or near quota limits.

  Returns `:ok` if usage is under the threshold, `{:warning, resources}` if
  nearing limits (>80%), or `{:error, resources}` if at limits.

  ## Examples

      :ok = QuotaService.check_quota_health(org_id)
      {:warning, [:missions]} = QuotaService.check_quota_health(org_id)
  """
  @spec check_quota_health(org_id(), threshold :: float()) ::
          :ok | {:warning, [atom()]} | {:error, [atom()]} | {:error, :not_found}
  def check_quota_health(org_id, threshold \\ 0.8) do
    with {:ok, usage} <- get_quota_usage(org_id) do
      at_limit = Enum.filter(usage, fn {_k, v} -> v >= 100.0 end) |> Keyword.keys()

      near_limit =
        Enum.filter(usage, fn {_k, v} -> v >= threshold * 100 and v < 100 end) |> Keyword.keys()

      cond do
        length(at_limit) > 0 -> {:error, at_limit}
        length(near_limit) > 0 -> {:warning, near_limit}
        true -> :ok
      end
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp percentage(_current, 0), do: 0.0
  defp percentage(current, max), do: Float.round(current / max * 100, 1)
end
