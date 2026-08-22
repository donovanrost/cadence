defmodule Cadence.Recordings.Recordables.ContactBlocked do
  @moduledoc """
  Recordable for when a contact is blocked by resource contention.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :bidirectional]

  schema "contact_blockeds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :spacecraft_target_id, :binary_id
    field :ground_station_target_id, :binary_id
    field :antenna_id, :string
    field :direction, Ecto.Enum, values: @directions
    field :blocked_by_contact_id, :binary_id
    field :policy, :string
    field :message, :string
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
      :blocked_by_contact_id,
      :policy,
      :message,
      :details
    ])
    |> validate_required([
      :mission_id,
      :contact_id,
      :spacecraft_target_id,
      :ground_station_target_id,
      :antenna_id,
      :direction,
      :blocked_by_contact_id,
      :policy
    ])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ContactBlocked do
  def recording_type(_), do: "ContactBlocked"
  def aggregate_type(_), do: "Contact"
  def title(_), do: "Contact Blocked"
  def status(_), do: "blocked"
  def severity(_), do: :warning
end
