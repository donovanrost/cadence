defmodule Cadence.Recordings.Recordables.ContactActivationFailed do
  @moduledoc """
  Recordable for when a contact fails to activate transports.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions [:uplink, :downlink, :bidirectional]

  schema "contact_activation_faileds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :spacecraft_target_id, :binary_id
    field :ground_station_target_id, :binary_id
    field :antenna_id, :string
    field :direction, Ecto.Enum, values: @directions
    field :error_code, :string
    field :error_message, :string
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
      :error_code,
      :error_message,
      :details
    ])
    |> validate_required([
      :mission_id,
      :contact_id,
      :spacecraft_target_id,
      :ground_station_target_id,
      :antenna_id,
      :direction,
      :error_code
    ])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ContactActivationFailed do
  def recording_type(_), do: "ContactActivationFailed"
  def aggregate_type(_), do: "Contact"
  def title(_), do: "Contact Activation Failed"
  def status(_), do: "failed"
  def severity(_), do: :critical
end
