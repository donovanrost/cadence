defmodule Cadence.Domain.Organizations.ValueObjects.Quotas do
  @moduledoc """
  Value object representing organization resource quotas.

  Quotas define the limits for various resources an organization can use.
  Each quota can be checked against current usage to enforce limits.
  """

  alias Cadence.Domain.Organizations.ValueObjects.SubscriptionTier

  @type t :: %__MODULE__{
          max_missions: pos_integer(),
          max_targets_per_mission: pos_integer(),
          max_users: pos_integer(),
          storage_quota_gb: pos_integer()
        }

  @enforce_keys [:max_missions, :max_targets_per_mission, :max_users, :storage_quota_gb]
  defstruct [:max_missions, :max_targets_per_mission, :max_users, :storage_quota_gb]

  @doc """
  Creates a new Quotas value object with the given values.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, max_missions} <- validate_positive_integer(attrs, :max_missions),
         {:ok, max_targets} <- validate_positive_integer(attrs, :max_targets_per_mission),
         {:ok, max_users} <- validate_positive_integer(attrs, :max_users),
         {:ok, storage} <- validate_positive_integer(attrs, :storage_quota_gb) do
      {:ok,
       %__MODULE__{
         max_missions: max_missions,
         max_targets_per_mission: max_targets,
         max_users: max_users,
         storage_quota_gb: storage
       }}
    end
  end

  @doc """
  Creates quotas from a subscription tier's defaults.
  """
  @spec from_tier(SubscriptionTier.t()) :: t()
  def from_tier(tier) do
    defaults = SubscriptionTier.default_quotas(tier)

    %__MODULE__{
      max_missions: defaults.max_missions,
      max_targets_per_mission: defaults.max_targets_per_mission,
      max_users: defaults.max_users,
      storage_quota_gb: defaults.storage_quota_gb
    }
  end

  @doc """
  Creates quotas from a map, typically from database fields.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      max_missions: Map.get(map, :max_missions, 5),
      max_targets_per_mission: Map.get(map, :max_targets_per_mission, 10),
      max_users: Map.get(map, :max_users, 10),
      storage_quota_gb: Map.get(map, :storage_quota_gb, 10)
    }
  end

  @doc """
  Converts quotas to a plain map for persistence.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = quotas) do
    %{
      max_missions: quotas.max_missions,
      max_targets_per_mission: quotas.max_targets_per_mission,
      max_users: quotas.max_users,
      storage_quota_gb: quotas.storage_quota_gb
    }
  end

  @doc """
  Checks if adding a mission would exceed the quota.
  Returns :ok if within quota, {:error, :quota_exceeded} otherwise.
  """
  @spec check_mission_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_mission_quota(%__MODULE__{max_missions: max}, current_count) do
    if current_count < max do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Checks if adding a target to a mission would exceed the quota.
  """
  @spec check_target_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_target_quota(%__MODULE__{max_targets_per_mission: max}, current_count) do
    if current_count < max do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Checks if adding a user would exceed the quota.
  """
  @spec check_user_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_user_quota(%__MODULE__{max_users: max}, current_count) do
    if current_count < max do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Checks if storage usage would exceed the quota.
  """
  @spec check_storage_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_storage_quota(%__MODULE__{storage_quota_gb: max}, current_gb) do
    if current_gb < max do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Returns the remaining capacity for missions.
  """
  @spec remaining_missions(t(), non_neg_integer()) :: non_neg_integer()
  def remaining_missions(%__MODULE__{max_missions: max}, current_count) do
    max(0, max - current_count)
  end

  @doc """
  Returns the remaining capacity for targets per mission.
  """
  @spec remaining_targets(t(), non_neg_integer()) :: non_neg_integer()
  def remaining_targets(%__MODULE__{max_targets_per_mission: max}, current_count) do
    max(0, max - current_count)
  end

  @doc """
  Returns the remaining capacity for users.
  """
  @spec remaining_users(t(), non_neg_integer()) :: non_neg_integer()
  def remaining_users(%__MODULE__{max_users: max}, current_count) do
    max(0, max - current_count)
  end

  @doc """
  Returns the remaining storage in GB.
  """
  @spec remaining_storage_gb(t(), non_neg_integer()) :: non_neg_integer()
  def remaining_storage_gb(%__MODULE__{storage_quota_gb: max}, current_gb) do
    max(0, max - current_gb)
  end

  @doc """
  Updates specific quota values, returning a new Quotas struct.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = quotas, attrs) when is_map(attrs) do
    new_attrs = %{
      max_missions: Map.get(attrs, :max_missions, quotas.max_missions),
      max_targets_per_mission:
        Map.get(attrs, :max_targets_per_mission, quotas.max_targets_per_mission),
      max_users: Map.get(attrs, :max_users, quotas.max_users),
      storage_quota_gb: Map.get(attrs, :storage_quota_gb, quotas.storage_quota_gb)
    }

    new(new_attrs)
  end

  # Private helpers

  defp validate_positive_integer(attrs, key) do
    case Map.get(attrs, key) do
      nil ->
        {:error, {:missing_required, key}}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_integer(value) ->
        {:error, {:must_be_positive, key, value}}

      value ->
        {:error, {:invalid_type, key, value}}
    end
  end
end
