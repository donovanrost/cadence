defmodule Cadence.Procedures.ProcedureLog do
  @moduledoc """
  Log entries for procedure executions.

  Captures messages from `cadence.log()` calls, step transitions, and errors.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.ProcedureExecution

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @levels [:debug, :info, :warn, :error]

  schema "procedure_logs" do
    field :timestamp, :utc_datetime_usec
    field :level, Ecto.Enum, values: @levels, default: :info
    field :message, :string
    field :step_index, :integer
    field :metadata, :map, default: %{}

    belongs_to :execution, ProcedureExecution

    # No timestamps - we use the explicit timestamp field
  end

  @required_fields [:execution_id, :timestamp, :message]
  @optional_fields [:level, :step_index, :metadata]

  def changeset(log, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:message, max: 10_000)
    |> foreign_key_constraint(:execution_id)
  end

  def levels, do: @levels
end
