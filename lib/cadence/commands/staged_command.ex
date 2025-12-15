defmodule Cadence.Commands.StagedCommand do
  @moduledoc """
  Schema for staged commands in the mission's workbench.

  Staged commands represent commands that operators have prepared but not yet
  queued for execution. They persist across page refreshes and browser sessions,
  allowing operators to build up command sequences before committing them.

  ## Visibility

  Staged commands are shared across the mission team - all operators on a mission
  can see and manage staged commands. The `created_by_user_id` tracks who originally
  staged the command for audit purposes.

  ## Relationship to Queue

  Staged commands are distinct from QueueEntry:
  - StagedCommand: Operator's draft/workspace (editable, not executing)
  - QueueEntry: Committed for execution (immutable once queued)

  When an operator "queues" a staged command, it creates QueueEntry records
  and deletes the staged command (or its target entries).

  ## Priority Levels

  - 0: Emergency (immediate, bypasses queue)
  - 1: Critical
  - 2: High
  - 3: Normal (default)
  - 4: Low
  - 5: Background
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission
  alias Cadence.Accounts.User
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Commands.StagedCommandTarget

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @priority_levels [0, 1, 2, 3, 4, 5]

  schema "staged_commands" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :created_by_user, User, foreign_key: :created_by_user_id
    belongs_to :meta_command, MetaCommand

    # Denormalized command name for display if meta_command is deleted
    field :command_name, :string

    # Queue settings
    field :priority, :integer, default: 3

    # Client-generated ID for optimistic UI deduplication
    field :client_id, :string

    has_many :targets, StagedCommandTarget, on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new staged command.
  """
  def changeset(staged_command, attrs) do
    staged_command
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :created_by_user_id,
      :meta_command_id,
      :command_name,
      :priority,
      :client_id
    ])
    |> validate_required([
      :organization_id,
      :mission_id,
      :meta_command_id,
      :command_name
    ])
    |> validate_inclusion(:priority, @priority_levels)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:created_by_user_id)
    |> foreign_key_constraint(:meta_command_id)
  end

  @doc """
  Changeset for updating priority.
  """
  def priority_changeset(staged_command, priority) do
    staged_command
    |> cast(%{priority: priority}, [:priority])
    |> validate_inclusion(:priority, @priority_levels)
  end

  @doc """
  Returns the list of valid priority levels.
  """
  def priority_levels, do: @priority_levels
end
