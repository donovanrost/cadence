defmodule Cadence.Recordings.Recordables.ProcedureApprovalAdded do
  @moduledoc """
  Recordable for when an approval/rejection is added to a procedure version.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @decisions ["approved", "rejected"]

  schema "procedure_approval_addeds" do
    field :decision, :string
    field :comment, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:decision]
  @optional_fields [:comment]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:decision, @decisions)
  end

  def decisions, do: @decisions
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ProcedureApprovalAdded do
  def recording_type(_), do: "ProcedureApprovalAdded"
  def aggregate_type(_), do: "ProcedureVersion"
  def title(r), do: "Review: #{r.decision}"
  def status(_), do: "pending_review"
  def severity(_), do: nil
end
