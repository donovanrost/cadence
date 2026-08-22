defmodule Cadence.Recordings.Recordables.CommandDispatched do
  @moduledoc """
  Recordable for when a command is dispatched.

  This is the "rich" recordable for commands - it contains all the command
  details since this is the initial event that captures what was requested.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_dispatcheds" do
    field :command_name, :string
    field :opcode, :integer
    field :parameters, :map, default: %{}
    field :encoded_binary, :binary
    field :meta_command_id, :binary_id
    field :is_hazardous, :boolean, default: false

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:command_name]
  @optional_fields [:opcode, :parameters, :encoded_binary, :meta_command_id, :is_hazardous]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandDispatched do
  def recording_type(_), do: "CommandDispatched"
  def aggregate_type(_), do: "Command"
  def title(r), do: r.command_name
  def status(_), do: "pending"
  def severity(_), do: nil
end
