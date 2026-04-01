defmodule Cadence.Recordings.Recordables.StepActivated do
  @moduledoc """
  Recordable for when a procedure step is activated for operator interaction.

  This event marks when a step becomes available for the operator to work on.
  Steps are activated when their dependencies are satisfied.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "step_activateds" do
    field :step_name, :string
    field :step_title, :string
    field :section_name, :string
    field :step_position, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:step_name]
  @optional_fields [:step_title, :section_name, :step_position]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.StepActivated do
  def recording_type(_), do: "StepActivated"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: "Step activated: #{r.step_title || r.step_name}"
  def status(_), do: "active"
  def severity(_), do: nil
end
