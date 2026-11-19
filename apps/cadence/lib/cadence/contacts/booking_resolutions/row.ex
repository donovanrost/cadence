defmodule Cadence.Contacts.BookingResolutions.Row do
  @moduledoc "An operator's resolution of one unconfirmed booking, with its conflict state (#53/#54)."
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @actions ~w(booked not_booked)
  @outcomes ~w(provider_answered attested not_booked)
  @conflicts ~w(cancel_failed late_confirmation contradicts_attestation)
  @conflict_states ~w(open acknowledged resolved)

  @primary_key {:booking_resolution_id, :string, autogenerate: false}
  schema "booking_resolutions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:contact_plan_execution_item_id, :string)
    field(:provider_reservation_id, :string)
    field(:provider_contact_ref, :string)
    field(:scheduled_contact_id, :string)
    field(:spacecraft_id, :string)
    field(:ground_station_ref, :string)
    field(:provider_id, :string)
    field(:starts_at, :utc_datetime_usec)
    field(:ends_at, :utc_datetime_usec)
    field(:action, :string)
    field(:outcome, :string)
    field(:provider_reference, :string)
    field(:note, :string)
    field(:actor_document, :map)
    field(:provider_answer_document, :map, default: %{})
    field(:conflict, :string)
    field(:conflict_state, :string)
    field(:conflict_document, :map, default: %{})
    field(:conflict_raised_at, :utc_datetime_usec)
    field(:conflict_acknowledged_at, :utc_datetime_usec)
    field(:conflict_acknowledged_by, :map)
    field(:conflict_resolved_at, :utc_datetime_usec)
    field(:conflict_resolved_by, :map)
    field(:conflict_resolution_action, :string)
    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(booking_resolution_id organization_id mission_id contact_plan_id contact_plan_version
    contact_plan_execution_item_id provider_reservation_id provider_contact_ref
    scheduled_contact_id spacecraft_id ground_station_ref provider_id starts_at ends_at action
    outcome provider_reference note actor_document provider_answer_document)a

  @required ~w(booking_resolution_id organization_id mission_id contact_plan_id
    contact_plan_version contact_plan_execution_item_id provider_reservation_id spacecraft_id
    provider_id starts_at ends_at action outcome note actor_document)a

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint(:contact_plan_execution_item_id)
  end

  @doc "Raises (or re-raises) a conflict; an acknowledged one of the same kind stays acknowledged."
  @spec conflict_changeset(t(), String.t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def conflict_changeset(%__MODULE__{} = row, conflict, document, now) do
    state = if row.conflict == conflict, do: row.conflict_state || "open", else: "open"

    row
    |> change(%{
      conflict: conflict,
      conflict_state: state,
      conflict_document: document,
      conflict_raised_at: if(state == "open", do: now, else: row.conflict_raised_at),
      conflict_resolved_at: nil,
      conflict_resolved_by: nil,
      conflict_resolution_action: nil
    })
    |> validate_inclusion(:conflict, @conflicts)
  end

  @spec state_changeset(t(), map()) :: Ecto.Changeset.t()
  def state_changeset(%__MODULE__{} = row, attrs) do
    row
    |> cast(attrs, ~w(conflict_state conflict_acknowledged_at conflict_acknowledged_by
      conflict_resolved_at conflict_resolved_by conflict_resolution_action
      provider_answer_document)a)
    |> validate_inclusion(:conflict_state, @conflict_states)
  end
end
