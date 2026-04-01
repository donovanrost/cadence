defmodule Cadence.Recordings.Recordables.ContactSkipped do
  @moduledoc """
  Recordable for when a contact is skipped after its window expires.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :bidirectional]

  schema "contact_skippeds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :spacecraft_target_id, :binary_id
    field :ground_station_target_id, :binary_id
    field :antenna_id, :string
    field :direction, Ecto.Enum, values: @directions
    field :reason, :string, default: "resource_unavailable"
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [
      :mission_id,
      :contact_id,
      :spacecraft_target_id,
      :ground_station_target_id,
      :antenna_id,
      :direction,
      :reason,
      :details
    ])
    |> validate_required([
      :mission_id,
      :contact_id,
      :spacecraft_target_id,
      :ground_station_target_id,
      :antenna_id,
      :direction,
      :reason
    ])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ContactSkipped do
  def recording_type(_), do: "ContactSkipped"
  def aggregate_type(_), do: "Contact"
  def title(_), do: "Contact Skipped"
  def status(_), do: "skipped"
  def severity(_), do: :warning
end
