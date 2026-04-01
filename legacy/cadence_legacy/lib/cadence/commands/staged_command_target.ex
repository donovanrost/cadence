defmodule Cadence.Commands.StagedCommandTarget do
  @moduledoc """
  Schema for target entries within a staged command.

  Each staged command can have multiple target entries, each with its own
  parameter values. This allows operators to:
  - Send the same command to multiple targets with different parameters
  - Edit parameters for one target without affecting others
  - Queue individual targets from a multi-target staged command
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Commands.StagedCommand
  alias Cadence.Targets.Target

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "staged_command_targets" do
    belongs_to :staged_command, StagedCommand
    belongs_to :target, Target

    # Denormalized target name for display if target is deleted
    field :target_name, :string

    # Per-target command parameters
    field :params, :map, default: %{}

    # Position for ordering within the staged command
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new target entry.
  """
  def changeset(target_entry, attrs) do
    target_entry
    |> cast(attrs, [:staged_command_id, :target_id, :target_name, :params, :position])
    |> validate_required([:staged_command_id, :target_id, :target_name])
    |> foreign_key_constraint(:staged_command_id)
    |> foreign_key_constraint(:target_id)
    |> unique_constraint([:staged_command_id, :target_id])
  end

  @doc """
  Changeset for updating parameters.
  """
  def params_changeset(target_entry, params) do
    target_entry
    |> cast(%{params: params}, [:params])
  end
end
