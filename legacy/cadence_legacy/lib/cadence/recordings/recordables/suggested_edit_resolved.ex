defmodule Cadence.Recordings.Recordables.SuggestedEditResolved do
  @moduledoc """
  Recordable for when a suggested edit is accepted or rejected.

  This event captures the resolution of a redline, completing the
  feedback loop from operator suggestion to procedure owner decision.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suggested_edit_resolveds" do
    field :edit_type, :string
    field :resolution, :string
    field :target_step_name, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:edit_type, :resolution]
  @optional_fields [:target_step_name]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.SuggestedEditResolved do
  def recording_type(_), do: "SuggestedEditResolved"
  def aggregate_type(_), do: "ProcedureExecution"

  def title(r) do
    action = if r.resolution == "accepted", do: "accepted", else: "rejected"
    "Redline #{action}: #{r.edit_type}"
  end

  def status(r), do: "redline_#{r.resolution}"
  def severity(_), do: nil
end
