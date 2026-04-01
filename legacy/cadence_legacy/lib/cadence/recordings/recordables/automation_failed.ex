defmodule Cadence.Recordings.Recordables.AutomationFailed do
  @moduledoc """
  Recordable for when an automation fails.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "automation_faileds" do
    field :error_message, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:error_message])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AutomationFailed do
  def recording_type(_), do: "AutomationFailed"
  def aggregate_type(_), do: "Automation"
  def title(r), do: r.error_message || "Failed"
  def status(_), do: "failed"
  def severity(_), do: "error"
end
