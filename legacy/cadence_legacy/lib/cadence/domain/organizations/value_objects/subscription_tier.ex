defmodule Cadence.Domain.Organizations.ValueObjects.SubscriptionTier do
  @moduledoc """
  Value object representing organization subscription tier.

  ## Tier Values

  - `:free` - Basic tier with limited resources
  - `:pro` - Professional tier with increased limits
  - `:enterprise` - Enterprise tier with maximum resources

  Each tier defines default quotas that can be customized per organization.
  """

  @type t :: :free | :pro | :enterprise

  @values [:free, :pro, :enterprise]

  @default_quotas %{
    free: %{
      max_missions: 5,
      max_targets_per_mission: 10,
      max_users: 10,
      storage_quota_gb: 10
    },
    pro: %{
      max_missions: 25,
      max_targets_per_mission: 50,
      max_users: 50,
      storage_quota_gb: 100
    },
    enterprise: %{
      max_missions: 100,
      max_targets_per_mission: 200,
      max_users: 500,
      storage_quota_gb: 1000
    }
  }

  @doc """
  Returns all valid tier values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the default tier for new organizations.
  """
  @spec default() :: t()
  def default, do: :free

  @doc """
  Returns true if the given value is a valid tier.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a tier value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_tier}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_tier}

  @doc """
  Parses a string or atom into a tier.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_tier}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "free" -> {:ok, :free}
      "pro" -> {:ok, :pro}
      "enterprise" -> {:ok, :enterprise}
      _ -> {:error, :invalid_tier}
    end
  end

  def parse(_), do: {:error, :invalid_tier}

  @doc """
  Returns the default quotas for a tier.
  """
  @spec default_quotas(t()) :: map()
  def default_quotas(tier) when tier in @values do
    Map.fetch!(@default_quotas, tier)
  end

  @doc """
  Returns true if the tier allows upgrading to the target tier.
  """
  @spec can_upgrade_to?(t(), t()) :: boolean()
  def can_upgrade_to?(current, target) do
    tier_level(target) > tier_level(current)
  end

  @doc """
  Returns true if the tier allows downgrading to the target tier.
  """
  @spec can_downgrade_to?(t(), t()) :: boolean()
  def can_downgrade_to?(current, target) do
    tier_level(target) < tier_level(current)
  end

  @doc """
  Returns the numeric level of a tier for comparison.
  """
  @spec tier_level(t()) :: non_neg_integer()
  def tier_level(:free), do: 0
  def tier_level(:pro), do: 1
  def tier_level(:enterprise), do: 2

  @doc """
  Returns the display name for a tier.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:free), do: "Free"
  def display_name(:pro), do: "Professional"
  def display_name(:enterprise), do: "Enterprise"

  @doc """
  Returns a color for the tier (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:free), do: "gray"
  def color(:pro), do: "blue"
  def color(:enterprise), do: "purple"
end
