defmodule Cadence.Contacts.PassResults.Row do
  @moduledoc "One booked pass's result (S9), keyed by its provider reservation."
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:provider_reservation_id, :string, autogenerate: false}
  schema "contact_pass_results" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_id, :string)
    field(:scheduled_contact_id, :string)
    field(:realized_contact_id, :string)
    field(:spacecraft_id, :string)
    field(:ground_station_ref, :string)
    field(:antenna_ref, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:planned_aos, :utc_datetime_usec)
    field(:planned_los, :utc_datetime_usec)
    field(:actual_aos, :utc_datetime_usec)
    field(:actual_los, :utc_datetime_usec)
    field(:planned_seconds, :integer)
    field(:flown_seconds, :integer)
    field(:planned_bytes, :integer)
    field(:provider_bytes, :integer)
    field(:provider_frames, :integer)
    field(:provider_packets, :integer)
    field(:received_bytes, :integer)
    field(:received_frames, :integer)
    field(:observations, :map, default: %{})
    field(:outcome, :string)
    field(:cause, :string)
    field(:cause_source, :string)
    field(:owner, :string, default: "unknown")
    field(:disputable, :boolean, default: false)
    field(:provider_reported_at, :utc_datetime_usec)
    field(:provider_revision, :integer)
    field(:closed_at, :utc_datetime_usec)
    field(:result_document, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(provider_reservation_id organization_id mission_id provider_id scheduled_contact_id
    realized_contact_id spacecraft_id ground_station_ref antenna_ref contact_plan_id
    contact_plan_version planned_aos planned_los actual_aos actual_los planned_seconds
    flown_seconds planned_bytes provider_bytes provider_frames provider_packets received_bytes
    received_frames observations
    outcome cause cause_source owner disputable provider_reported_at provider_revision closed_at
    result_document)a

  @required ~w(provider_reservation_id organization_id mission_id provider_id spacecraft_id
    planned_aos planned_los planned_seconds outcome owner)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:outcome, ~w(realized partial missed failed canceled pending_report))
    |> validate_inclusion(:owner, ~w(provider us weather unknown))
  end

  @spec replace_fields() :: [atom()]
  def replace_fields, do: (@fields -- [:provider_reservation_id]) ++ [:updated_at]
end
