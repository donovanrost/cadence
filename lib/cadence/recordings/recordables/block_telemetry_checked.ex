defmodule Cadence.Recordings.Recordables.BlockTelemetryChecked do
  @moduledoc """
  Recordable for when a telemetry check block is evaluated.

  This event captures the result of telemetry validation, including
  the actual value, pass criteria, and whether it passed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "block_telemetry_checkeds" do
    field :step_name, :string
    field :block_name, :string
    field :item_path, :string
    field :value, :string
    field :pass_criteria, :string
    field :passed, :boolean

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:step_name, :item_path, :passed]
  @optional_fields [:block_name, :value, :pass_criteria]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.BlockTelemetryChecked do
  def recording_type(_), do: "BlockTelemetryChecked"
  def aggregate_type(_), do: "ProcedureExecution"

  def title(r) do
    result = if r.passed, do: "PASS", else: "FAIL"
    "Check #{r.item_path}: #{r.value} #{result}"
  end

  def status(r), do: if(r.passed, do: "passed", else: "failed")
  def severity(r), do: if(r.passed, do: nil, else: "warning")
end
