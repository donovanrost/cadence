defmodule Cadence.Recordings.Recordables.CommandErrored do
  @moduledoc """
  Recordable for when a command encounters an error.

  Errors include transmission failures, encoding problems, or
  interface issues.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_erroreds" do
    field :error_reason, :string
    field :error_type, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:error_reason, :error_type])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandErrored do
  def recording_type(_), do: "CommandErrored"
  def aggregate_type(_), do: "Command"
  def title(r), do: "Error: #{r.error_type || "unknown"}"
  def status(_), do: "error"
  def severity(_), do: "error"
end
