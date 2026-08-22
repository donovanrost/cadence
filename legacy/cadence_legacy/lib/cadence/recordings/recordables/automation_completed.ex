defmodule Cadence.Recordings.Recordables.AutomationCompleted do
  @moduledoc """
  Recordable for when an automation completes successfully.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "automation_completeds" do
    field :action_result, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:action_result])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AutomationCompleted do
  def recording_type(_), do: "AutomationCompleted"
  def aggregate_type(_), do: "Automation"
  def title(_), do: "Completed"
  def status(_), do: "completed"
  def severity(_), do: nil
end
