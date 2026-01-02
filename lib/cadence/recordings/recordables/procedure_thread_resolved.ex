defmodule Cadence.Recordings.Recordables.ProcedureThreadResolved do
  @moduledoc """
  Recordable for when a review thread is marked as resolved.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_thread_resolveds" do
    field :thread_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:thread_id])
    |> validate_required([:thread_id])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureThreadResolved do
  def recording_type(_), do: "ProcedureThreadResolved"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Thread resolved"
  def status(_), do: nil
  def severity(_), do: nil
end
