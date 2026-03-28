defmodule Cadence.Contacts.Contact do
  @moduledoc """
  Planned contact window for a mission.

  Contacts are part of mission configuration and define expected
  communication windows. Execution state is derived from recordings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :bidirectional]
  @states [:planned, :cancelled]

  schema "contacts" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    field :spacecraft_target_id, :binary_id
    field :ground_station_target_id, :binary_id

    field :antenna_id, :string
    field :start_time, :utc_datetime_usec
    field :end_time, :utc_datetime_usec
    field :direction, Ecto.Enum, values: @directions
    field :state, Ecto.Enum, values: @states, default: :planned
    field :priority, :integer, default: 0
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :spacecraft_target_id,
      :ground_station_target_id,
      :antenna_id,
      :start_time,
      :end_time,
      :direction,
      :state,
      :priority,
      :metadata
    ])
    |> validate_required([
      :organization_id,
      :mission_id,
      :spacecraft_target_id,
      :ground_station_target_id,
      :antenna_id,
      :start_time,
      :end_time,
      :direction,
      :state,
      :priority
    ])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_time_range()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:spacecraft_target_id)
    |> foreign_key_constraint(:ground_station_target_id)
  end

  defp validate_time_range(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(start_time, end_time) != :lt do
      add_error(changeset, :end_time, "must be after start_time")
    else
      changeset
    end
  end
end
