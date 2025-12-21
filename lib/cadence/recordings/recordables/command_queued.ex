defmodule Cadence.Recordings.Recordables.CommandQueued do
  @moduledoc """
  Recordable for when a command is added to the queue.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_queueds" do
    field :command_name, :string
    field :parameters, :map, default: %{}
    field :priority, :integer, default: 3
    field :scheduled_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :max_attempts, :integer, default: 3
    field :dispatch_opts, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:command_name]
  @optional_fields [:parameters, :priority, :scheduled_at, :expires_at, :max_attempts, :dispatch_opts]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandQueued do
  def recording_type(_), do: "CommandQueued"
  def aggregate_type(_), do: "QueueEntry"
  def title(r), do: "Queued: #{r.command_name}"
  def status(_), do: "pending"
  def severity(_), do: nil
end
