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

  alias Cadence.Time, as: CadenceTime

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          name: String.t(),
          identifier: String.t(),
          scid: integer() | nil,
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
    field :scid, :integer
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

    # The C&T database version this target uses (required)
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    # Bucket for hierarchical organization (target group)
    belongs_to :bucket, Cadence.Buckets.Bucket

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new target.
  """
  def changeset(target, attrs) do
    target
    |> cast(attrs, [
      :mission_id,
      :definition_set_id,
      :name,
      :identifier,
      :scid,
      :type,
      :status,
      :config,
      :metadata,
      :active_limit_set
    ])
    |> validate_required([:mission_id, :definition_set_id, :name, :identifier, :type])
    |> validate_format(:identifier, ~r/^[A-Z0-9_-]+$/,
      message: "must be uppercase alphanumeric with underscores/hyphens"
    )
    |> validate_scid()
    |> validate_inclusion(:type, ["spacecraft", "ground_station", "simulator", "relay"])
    |> validate_inclusion(:status, ["offline", "online", "standby", "fault"])
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:definition_set_id)
    |> unique_constraint([:mission_id, :identifier])
    |> unique_constraint([:mission_id, :scid], name: :targets_mission_scid_index)
  end

  @doc """
  Changeset for updating target status or configuration.
  """
  def update_changeset(target, attrs) do
    target
    |> cast(attrs, [
      :name,
      :status,
      :config,
      :metadata,
      :active_limit_set,
      :definition_set_id,
      :scid
    ])
    |> validate_required([:name])
    |> validate_scid()
    |> validate_inclusion(:status, ["offline", "online", "standby", "fault"])
    |> foreign_key_constraint(:definition_set_id)
  end

  defp validate_scid(changeset) do
    type = get_field(changeset, :type)
    scid = get_field(changeset, :scid)

    changeset =
      if type == "spacecraft" do
        validate_required(changeset, [:scid])
      else
        changeset
      end

    if is_nil(scid) do
      changeset
    else
      validate_number(changeset, :scid, greater_than_or_equal_to: 0, less_than: 1024)
    end
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
      circuit_breaker_opened_at: CadenceTime.now()
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

  @doc """
  Creates a changeset to assign a definition set to a target.
  """
  def assign_definition_set(target, definition_set_id) do
    target
    |> cast(%{definition_set_id: definition_set_id}, [:definition_set_id])
    |> foreign_key_constraint(:definition_set_id)
  end
end
