defmodule Cadence.Comms.StationAvailability.WindowRow do
  @moduledoc "One availability window of a ground station (outage, maintenance or degraded)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:window_id, :string, autogenerate: false}
  schema "ground_station_availability_windows" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:ground_station_id, :string)
    field(:kind, :string)
    field(:starts_at, :utc_datetime_usec)
    field(:ends_at, :utc_datetime_usec)
    field(:eta, :utc_datetime_usec)
    field(:source, :string)
    field(:reported_by, :map, default: %{})
    field(:provider_ref, :string)
    field(:reason, :string)
    field(:detail, :map, default: %{})
    field(:cleared_at, :utc_datetime_usec)
    field(:cleared_by, :map)
    timestamps(type: :utc_datetime_usec)
  end
end
