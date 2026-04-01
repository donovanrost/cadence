defmodule Cadence.Recordings.Recordables.AutomationTriggered do
  @moduledoc """
  Recordable for when an automation is triggered.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "automation_triggereds" do
    field :automation_id, :binary_id
    field :trigger_event, :map
    field :trigger_type, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:automation_id]
  @optional_fields [:trigger_event, :trigger_type]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AutomationTriggered do
  def recording_type(_), do: "AutomationTriggered"
  def aggregate_type(_), do: "Automation"
  def title(r), do: "Triggered (#{r.trigger_type || "unknown"})"
  def status(_), do: "running"
  def severity(_), do: nil
end
