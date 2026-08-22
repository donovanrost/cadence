defmodule Cadence.Domain.Organizations.ValueObjects.OrganizationStatus do
  @moduledoc """
  Value object representing organization status.

  ## Status Values

  - `:active` - Organization is operational and can be used
  - `:suspended` - Organization is temporarily disabled (e.g., billing issues)
  - `:terminated` - Organization has been permanently closed

  ## State Machine

  ```
  ┌────────┐    suspend    ┌───────────┐
  │ ACTIVE │ ─────────────►│ SUSPENDED │
  └────────┘               └───────────┘
      ▲                         │
      │ reactivate              │ terminate
      └─────────────────────────┤
                                ▼
                          ┌────────────┐
                          │ TERMINATED │
                          └────────────┘
  ```
  """

  @type t :: :active | :suspended | :terminated

  @values [:active, :suspended, :terminated]

  @valid_transitions %{
    active: [:suspended, :terminated],
    suspended: [:active, :terminated],
    terminated: []
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial status for a new organization.
  """
  @spec initial() :: t()
  def initial, do: :active

  @doc """
  Returns true if the given value is a valid status.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a status value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_status}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_status}

  @doc """
  Parses a string or atom into a status.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_status}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "active" -> {:ok, :active}
      "suspended" -> {:ok, :suspended}
      "terminated" -> {:ok, :terminated}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the organization is operational.
  """
  @spec operational?(t()) :: boolean()
  def operational?(:active), do: true
  def operational?(_), do: false

  @doc """
  Returns true if the status is terminal.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(:terminated), do: true
  def terminal?(_), do: false

  @doc """
  Returns true if the organization can be reactivated.
  """
  @spec can_reactivate?(t()) :: boolean()
  def can_reactivate?(:suspended), do: true
  def can_reactivate?(_), do: false

  @doc """
  Returns the list of valid next states.
  """
  @spec valid_next_states(t()) :: [t()]
  def valid_next_states(status) when is_map_key(@valid_transitions, status) do
    Map.fetch!(@valid_transitions, status)
  end

  def valid_next_states(_), do: []

  @doc """
  Returns true if a transition is valid.
  """
  @spec can_transition?(t(), t()) :: boolean()
  def can_transition?(from, to) when from in @values and to in @values do
    to in Map.get(@valid_transitions, from, [])
  end

  def can_transition?(_, _), do: false

  @doc """
  Validates a transition.
  """
  @spec validate_transition(t(), t()) :: :ok | {:error, {:invalid_transition, t(), t()}}
  def validate_transition(from, to) do
    if can_transition?(from, to) do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  @doc """
  Returns the display name for a status.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:active), do: "Active"
  def display_name(:suspended), do: "Suspended"
  def display_name(:terminated), do: "Terminated"

  @doc """
  Returns a color for the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:active), do: "green"
  def color(:suspended), do: "yellow"
  def color(:terminated), do: "red"
end
