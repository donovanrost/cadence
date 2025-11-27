defmodule Cadence.Commands.CommandLog do
  @moduledoc """
  Audit log for command dispatch activity.

  Every command dispatch is logged with:
  - Who sent it (user)
  - When it was sent
  - What was sent (command name, parameters, encoded binary)
  - Where it went (target, interface)
  - What happened (status, verification result)

  This provides a complete audit trail for mission operations and can be used
  for post-flight analysis, anomaly investigation, and compliance.

  ## Status Values

  - `:pending` - Command is being processed
  - `:sent` - Command was transmitted to interface
  - `:verified` - Command verification succeeded
  - `:verification_failed` - Verification timed out or mismatched
  - `:rejected` - Command was rejected (validation, authorization, etc.)
  - `:error` - Transmission or encoding error

  ## Example

      %CommandLog{
        command_name: "SET_MODE",
        parameters: %{"mode" => 1},
        status: :verified,
        sent_at: ~U[2025-01-15 14:30:00Z],
        verified_at: ~U[2025-01-15 14:30:02Z]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission
  alias Cadence.Targets.Target
  alias Cadence.Commands.CommandDefinition
  alias Cadence.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:pending, :sent, :verified, :verification_failed, :rejected, :error]

  schema "command_logs" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :target, Target
    belongs_to :command_definition, CommandDefinition
    belongs_to :user, User

    # Command identification
    field :command_name, :string
    field :opcode, :integer

    # What was sent
    field :parameters, :map, default: %{}
    field :encoded_binary, :binary

    # Status and result
    field :status, Ecto.Enum, values: @status_values, default: :pending
    field :error_reason, :string

    # Verification tracking
    field :verification_item, :string
    field :verification_expected, :string
    field :verification_actual, :string
    field :verification_result, :map

    # Timestamps
    field :sent_at, :utc_datetime_usec
    field :verified_at, :utc_datetime_usec

    # Metadata (interface_id, etc.)
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new command log entry.
  """
  def changeset(command_log, attrs) do
    command_log
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :target_id,
      :command_definition_id,
      :user_id,
      :command_name,
      :opcode,
      :parameters,
      :encoded_binary,
      :status,
      :error_reason,
      :verification_item,
      :verification_expected,
      :verification_actual,
      :verification_result,
      :sent_at,
      :verified_at,
      :metadata
    ])
    |> validate_required([:organization_id, :mission_id, :command_name, :status])
    |> validate_inclusion(:status, @status_values)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
    |> foreign_key_constraint(:command_definition_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Updates status and related fields.
  """
  def status_changeset(command_log, attrs) do
    command_log
    |> cast(attrs, [
      :status,
      :error_reason,
      :verification_actual,
      :verification_result,
      :verified_at
    ])
    |> validate_inclusion(:status, @status_values)
  end

  @doc """
  Returns the list of valid status values.
  """
  def valid_statuses, do: @status_values
end
