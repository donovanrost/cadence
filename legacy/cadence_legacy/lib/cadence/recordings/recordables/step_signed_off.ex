defmodule Cadence.Recordings.Recordables.StepSignedOff do
  @moduledoc """
  Recordable for when an operator signs off on a procedure step.

  This event captures each signoff action, including the role used
  and progress toward meeting signoff requirements.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "step_signed_offs" do
    field :step_name, :string
    field :step_title, :string
    field :role, :string
    field :signoff_count, :integer
    field :signoffs_required, :integer
    field :step_result, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:step_name, :role]
  @optional_fields [:step_title, :signoff_count, :signoffs_required, :step_result]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.StepSignedOff do
  def recording_type(_), do: "StepSignedOff"
  def aggregate_type(_), do: "ProcedureExecution"

  def title(r) do
    step = r.step_title || r.step_name
    "Signed off: #{step} (#{r.role})"
  end

  def status(_), do: "signed_off"
  def severity(_), do: nil
end
