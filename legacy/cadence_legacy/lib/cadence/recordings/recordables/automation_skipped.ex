defmodule Cadence.Recordings.Recordables.AutomationSkipped do
  @moduledoc """
  Recordable for when an automation is skipped (condition not met).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "automation_skippeds" do
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:reason])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AutomationSkipped do
  def recording_type(_), do: "AutomationSkipped"
  def aggregate_type(_), do: "Automation"
  def title(r), do: r.reason || "Skipped"
  def status(_), do: "skipped"
  def severity(_), do: nil
end
