defmodule Cadence.Domain.Organizations.Entities.Organization do
  @moduledoc """
  Pure domain entity representing an organization (tenant) in the system.

  Organizations are the top-level container for all resources in the multi-tenant
  architecture. Each organization has its own missions, users, and isolated data.

  ## Usage

      {:ok, org} = Organization.new(%{
        name: "Acme Corp",
        slug: "acme-corp"
      })

      # Update organization
      {:ok, org} = Organization.update(org, %{name: "Acme Corporation"})

      # Check quotas
      :ok = Organization.check_mission_quota(org, current_mission_count)
  """

  alias Cadence.Domain.Organizations.ValueObjects.OrganizationStatus
  alias Cadence.Domain.Organizations.ValueObjects.SubscriptionTier
  alias Cadence.Domain.Organizations.ValueObjects.Quotas

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          slug: String.t(),
          status: OrganizationStatus.t(),
          subscription_tier: SubscriptionTier.t(),
          quotas: Quotas.t(),
          settings: map(),
          metadata: map(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :name,
    :slug,
    :status,
    :subscription_tier,
    :quotas,
    :created_at,
    :updated_at,
    settings: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new Organization entity.

  ## Required Fields

  - `:name` - Organization display name
  - `:slug` - URL-safe identifier (lowercase alphanumeric with hyphens)

  ## Optional Fields

  - `:status` - Organization status (default: :active)
  - `:subscription_tier` - Subscription tier (default: :free)
  - `:quotas` - Resource quotas (default: from tier)
  - `:settings` - Organization settings map
  - `:metadata` - Additional metadata map
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs, [:name, :slug]),
         :ok <- validate_name(attrs[:name]),
         :ok <- validate_slug(attrs[:slug]),
         {:ok, status} <- parse_status(attrs[:status]),
         {:ok, tier} <- parse_tier(attrs[:subscription_tier]),
         {:ok, quotas} <- build_quotas(attrs, tier) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         name: attrs[:name],
         slug: attrs[:slug],
         status: status,
         subscription_tier: tier,
         quotas: quotas,
         settings: attrs[:settings] || %{},
         metadata: attrs[:metadata] || %{},
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates the organization with new attributes.

  Note: slug cannot be changed after creation.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = org, attrs) do
    with :ok <- validate_name(attrs[:name] || org.name),
         {:ok, status} <- maybe_parse_status(attrs[:status], org.status),
         {:ok, tier} <- maybe_parse_tier(attrs[:subscription_tier], org.subscription_tier),
         {:ok, quotas} <- maybe_update_quotas(attrs, org.quotas) do
      {:ok,
       %{
         org
         | name: attrs[:name] || org.name,
           status: status,
           subscription_tier: tier,
           quotas: quotas,
           settings: Map.merge(org.settings, attrs[:settings] || %{}),
           metadata: Map.merge(org.metadata, attrs[:metadata] || %{}),
           updated_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Transitions the organization to a new status.
  """
  @spec transition_status(t(), OrganizationStatus.t()) :: {:ok, t()} | {:error, term()}
  def transition_status(%__MODULE__{status: current} = org, new_status) do
    with :ok <- OrganizationStatus.validate_transition(current, new_status) do
      {:ok, %{org | status: new_status, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Suspends the organization.
  """
  @spec suspend(t()) :: {:ok, t()} | {:error, term()}
  def suspend(%__MODULE__{} = org), do: transition_status(org, :suspended)

  @doc """
  Reactivates a suspended organization.
  """
  @spec reactivate(t()) :: {:ok, t()} | {:error, term()}
  def reactivate(%__MODULE__{} = org), do: transition_status(org, :active)

  @doc """
  Terminates the organization permanently.
  """
  @spec terminate(t()) :: {:ok, t()} | {:error, term()}
  def terminate(%__MODULE__{} = org), do: transition_status(org, :terminated)

  @doc """
  Returns true if the organization is active and operational.
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}), do: OrganizationStatus.operational?(status)

  @doc """
  Returns true if the organization is terminated.
  """
  @spec terminated?(t()) :: boolean()
  def terminated?(%__MODULE__{status: status}), do: OrganizationStatus.terminal?(status)

  @doc """
  Checks if adding a mission would exceed the quota.
  """
  @spec check_mission_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_mission_quota(%__MODULE__{quotas: quotas}, current_count) do
    Quotas.check_mission_quota(quotas, current_count)
  end

  @doc """
  Checks if adding a target to a mission would exceed the quota.
  """
  @spec check_target_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_target_quota(%__MODULE__{quotas: quotas}, current_count) do
    Quotas.check_target_quota(quotas, current_count)
  end

  @doc """
  Checks if adding a user would exceed the quota.
  """
  @spec check_user_quota(t(), non_neg_integer()) :: :ok | {:error, :quota_exceeded}
  def check_user_quota(%__MODULE__{quotas: quotas}, current_count) do
    Quotas.check_user_quota(quotas, current_count)
  end

  @doc """
  Updates the organization's quotas.
  """
  @spec update_quotas(t(), map()) :: {:ok, t()} | {:error, term()}
  def update_quotas(%__MODULE__{quotas: quotas} = org, attrs) do
    case Quotas.update(quotas, attrs) do
      {:ok, new_quotas} -> {:ok, %{org | quotas: new_quotas, updated_at: DateTime.utc_now()}}
      error -> error
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, fields) do
    missing = Enum.filter(fields, fn field -> is_nil(attrs[field]) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_name(nil), do: :ok

  defp validate_name(name) when is_binary(name) do
    cond do
      String.length(name) < 1 -> {:error, :name_too_short}
      String.length(name) > 255 -> {:error, :name_too_long}
      true -> :ok
    end
  end

  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_slug(nil), do: :ok

  defp validate_slug(slug) when is_binary(slug) do
    cond do
      String.length(slug) < 1 ->
        {:error, :slug_too_short}

      String.length(slug) > 100 ->
        {:error, :slug_too_long}

      not Regex.match?(~r/^[a-z0-9-]+$/, slug) ->
        {:error, :invalid_slug_format}

      true ->
        :ok
    end
  end

  defp validate_slug(_), do: {:error, :invalid_slug}

  defp parse_status(nil), do: {:ok, OrganizationStatus.initial()}

  defp parse_status(status) when is_atom(status) do
    if OrganizationStatus.valid?(status) do
      {:ok, status}
    else
      {:error, :invalid_status}
    end
  end

  defp parse_status(status) when is_binary(status), do: OrganizationStatus.parse(status)
  defp parse_status(_), do: {:error, :invalid_status}

  defp maybe_parse_status(nil, current), do: {:ok, current}
  defp maybe_parse_status(status, _current), do: parse_status(status)

  defp parse_tier(nil), do: {:ok, SubscriptionTier.default()}

  defp parse_tier(tier) when is_atom(tier) do
    if SubscriptionTier.valid?(tier) do
      {:ok, tier}
    else
      {:error, :invalid_tier}
    end
  end

  defp parse_tier(tier) when is_binary(tier), do: SubscriptionTier.parse(tier)
  defp parse_tier(_), do: {:error, :invalid_tier}

  defp maybe_parse_tier(nil, current), do: {:ok, current}
  defp maybe_parse_tier(tier, _current), do: parse_tier(tier)

  defp build_quotas(attrs, tier) do
    cond do
      # Explicit quotas provided as a Quotas struct
      match?(%Quotas{}, attrs[:quotas]) ->
        {:ok, attrs[:quotas]}

      # Explicit quota values provided
      has_quota_attrs?(attrs) ->
        Quotas.new(%{
          max_missions: attrs[:max_missions] || tier_default(tier, :max_missions),
          max_targets_per_mission:
            attrs[:max_targets_per_mission] || tier_default(tier, :max_targets_per_mission),
          max_users: attrs[:max_users] || tier_default(tier, :max_users),
          storage_quota_gb: attrs[:storage_quota_gb] || tier_default(tier, :storage_quota_gb)
        })

      # Use tier defaults
      true ->
        {:ok, Quotas.from_tier(tier)}
    end
  end

  defp maybe_update_quotas(attrs, current_quotas) do
    if has_quota_attrs?(attrs) do
      Quotas.update(current_quotas, attrs)
    else
      {:ok, current_quotas}
    end
  end

  defp has_quota_attrs?(attrs) do
    Enum.any?(
      [:max_missions, :max_targets_per_mission, :max_users, :storage_quota_gb],
      &Map.has_key?(attrs, &1)
    )
  end

  defp tier_default(tier, key) do
    defaults = SubscriptionTier.default_quotas(tier)
    Map.get(defaults, key)
  end
end
