defmodule Cadence.Targets.Target do
  @moduledoc """
  Target schema representing a spacecraft, ground station, or other entity within a mission.

  Targets are the endpoints that send telemetry and receive commands. Each target:
  - Belongs to exactly one mission
  - Has a unique identifier within the mission
  - Maintains circuit breaker state for command safety
  - Can be organized into hierarchical groups
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          name: String.t(),
          identifier: String.t(),
          type: String.t(),
          status: String.t(),
          config: map(),
          metadata: map(),
          active_limit_set: String.t(),
          circuit_breaker_status: String.t(),
          circuit_breaker_failures: integer(),
          circuit_breaker_opened_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "targets" do
    field :name, :string
    field :identifier, :string
    field :type, :string
    field :status, :string, default: "offline"

    # Configuration
    field :config, :map, default: %{}
    field :metadata, :map, default: %{}

    # Limits configuration
    field :active_limit_set, :string, default: "NOMINAL"

    # Command safety (circuit breaker pattern)
    field :circuit_breaker_status, :string, default: "closed"
    field :circuit_breaker_failures, :integer, default: 0
    field :circuit_breaker_opened_at, :utc_datetime

    # Associations
    belongs_to :mission, Cadence.Missions.Mission

    many_to_many :target_groups, Cadence.Targets.TargetGroup,
      join_through: "target_group_memberships"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new target.
  """
  def changeset(target, attrs) do
    target
    |> cast(attrs, [
      :mission_id,
      :name,
      :identifier,
      :type,
      :status,
      :config,
      :metadata,
      :active_limit_set
    ])
    |> validate_required([:mission_id, :name, :identifier, :type])
    |> validate_format(:identifier, ~r/^[A-Z0-9_-]+$/,
      message: "must be uppercase alphanumeric with underscores/hyphens"
    )
    |> validate_inclusion(:type, ["spacecraft", "ground_station", "simulator", "relay"])
    |> validate_inclusion(:status, ["offline", "online", "standby", "fault"])
    |> foreign_key_constraint(:mission_id)
    |> unique_constraint([:mission_id, :identifier])
  end

  @doc """
  Changeset for updating target status or configuration.
  """
  def update_changeset(target, attrs) do
    target
    |> cast(attrs, [:name, :status, :config, :metadata, :active_limit_set])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["offline", "online", "standby", "fault"])
  end

  @doc """
  Changeset for circuit breaker state changes.
  """
  def circuit_breaker_changeset(target, attrs) do
    target
    |> cast(attrs, [
      :circuit_breaker_status,
      :circuit_breaker_failures,
      :circuit_breaker_opened_at
    ])
    |> validate_required([:circuit_breaker_status])
    |> validate_inclusion(:circuit_breaker_status, ["closed", "open", "half_open"])
    |> validate_number(:circuit_breaker_failures, greater_than_or_equal_to: 0)
  end

  @doc """
  Opens the circuit breaker for a target after command failures.
  """
  def open_circuit_breaker(target) do
    circuit_breaker_changeset(target, %{
      circuit_breaker_status: "open",
      circuit_breaker_opened_at: DateTime.utc_now()
    })
  end

  @doc """
  Closes the circuit breaker, resetting failure count.
  """
  def close_circuit_breaker(target) do
    circuit_breaker_changeset(target, %{
      circuit_breaker_status: "closed",
      circuit_breaker_failures: 0,
      circuit_breaker_opened_at: nil
    })
  end

  @doc """
  Increments the failure count for circuit breaker logic.
  """
  def increment_failures(target) do
    circuit_breaker_changeset(target, %{
      circuit_breaker_failures: target.circuit_breaker_failures + 1
    })
  end
end
