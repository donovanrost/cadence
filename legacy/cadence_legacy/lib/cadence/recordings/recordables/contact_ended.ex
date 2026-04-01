defmodule Cadence.Recordings.Recordables.ContactEnded do
  @moduledoc """
  Recordable for when a contact ends.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :bidirectional]

  schema "contact_endeds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :spacecraft_target_id, :binary_id
    field :ground_station_target_id, :binary_id
    field :antenna_id, :string
    field :direction, Ecto.Enum, values: @directions
    field :reason, :string, default: "completed"

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
      :reason
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

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ContactEnded do
  def recording_type(_), do: "ContactEnded"
  def aggregate_type(_), do: "Contact"
  def title(_), do: "Contact Ended"
  def status(_), do: "ended"
  def severity(_), do: nil
end
