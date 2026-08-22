defmodule Cadence.Recordings.Recordables.ProcedureChangesRequested do
  @moduledoc """
  Recordable for when a reviewer requests changes on a procedure version.

  This creates a blocking review that must be addressed before the version
  can be approved.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_changes_requesteds" do
    field :body, :string
    field :thread_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:body, :thread_id])
    |> validate_required([:body])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureChangesRequested do
  def recording_type(_), do: "ProcedureChangesRequested"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(_), do: "Changes requested"
  def status(_), do: "changes_requested"
  def severity(_), do: nil
end
