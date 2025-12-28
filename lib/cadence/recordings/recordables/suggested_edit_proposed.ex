defmodule Cadence.Recordings.Recordables.SuggestedEditProposed do
  @moduledoc """
  Recordable for when an operator proposes a suggested edit (redline).

  This event captures when an operator suggests a change to the procedure
  during execution, creating a record for later review.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suggested_edit_proposeds" do
    field :edit_type, :string
    field :target_step_name, :string
    field :summary, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:edit_type]
  @optional_fields [:target_step_name, :summary]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.SuggestedEditProposed do
  def recording_type(_), do: "SuggestedEditProposed"
  def aggregate_type(_), do: "ProcedureExecution"

  def title(r) do
    summary = r.summary || r.edit_type
    "Redline proposed: #{summary}"
  end

  def status(_), do: "redline_proposed"
  def severity(_), do: nil
end
