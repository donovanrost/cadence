defmodule Cadence.Recordings.Recordables.CommandDequeued do
  @moduledoc """
  Recordable for when a command is removed from the queue.

  Reasons include: executed, cancelled, expired
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reasons ["executed", "cancelled", "expired"]

  schema "command_dequeueds" do
    field :reason, :string
    field :command_aggregate_id, :binary_id
    field :attempts, :integer
    field :last_error, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason, :command_aggregate_id, :attempts, :last_error])
    |> validate_inclusion(:reason, @reasons)
  end

  def reasons, do: @reasons
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandDequeued do
  def recording_type(_), do: "CommandDequeued"
  def aggregate_type(_), do: "QueueEntry"

  def title(r) do
    case r.reason do
      "executed" -> "Executed"
      "cancelled" -> "Cancelled"
      "expired" -> "Expired"
      _ -> "Dequeued"
    end
  end

  def status(r), do: r.reason || "dequeued"
  def severity(r), do: if(r.reason in ["cancelled", "expired"], do: "warning", else: nil)
end
