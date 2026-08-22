defmodule Cadence.Recordings.Recordables.CommandRejected do
  @moduledoc """
  Recordable for when a command is rejected.

  Commands can be rejected for validation failures, authorization issues,
  or phase restrictions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rejection_types ["validation", "authorization", "phase"]

  schema "command_rejecteds" do
    field :error_reason, :string
    field :rejection_type, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:error_reason, :rejection_type])
    |> validate_inclusion(:rejection_type, @rejection_types)
  end

  def rejection_types, do: @rejection_types
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandRejected do
  def recording_type(_), do: "CommandRejected"
  def aggregate_type(_), do: "Command"
  def title(r), do: "Rejected: #{r.rejection_type || "unknown"}"
  def status(_), do: "rejected"
  def severity(_), do: "error"
end
