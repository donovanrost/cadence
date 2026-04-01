defmodule Cadence.Recordings.Recordables.BlockValueEntered do
  @moduledoc """
  Recordable for when an operator enters a value into an input block.

  This event captures data entry during procedure execution, providing
  an audit trail of all operator inputs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "block_value_entereds" do
    field :step_name, :string
    field :block_name, :string
    field :block_type, :string
    field :value_summary, :string
    field :passed_validation, :boolean

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:step_name, :block_name]
  @optional_fields [:block_type, :value_summary, :passed_validation]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.BlockValueEntered do
  def recording_type(_), do: "BlockValueEntered"
  def aggregate_type(_), do: "ProcedureExecution"

  def title(r) do
    "Input: #{r.block_name} = #{r.value_summary || "(entered)"}"
  end

  def status(_), do: "input_entered"
  def severity(_), do: nil
end
