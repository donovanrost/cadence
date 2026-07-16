defmodule Cadence.Persistence.Schemas.ProviderReservationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:provider_reservation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "provider_reservations" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_id, :string)
    field(:provider_version, :integer)
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:provider_account_grant_id, :string)
    field(:provider_account_grant_version, :integer)
    field(:transport_id, :string)
    field(:transport_version, :integer)
    field(:service_profile_ref, :map, default: %{})
    field(:delivery_profile_ref, :map, default: %{})
    field(:provider_profile_id, :string)
    field(:provider_profile_version, :integer)
    field(:scheduled_contact_id, :string)
    field(:provider_opportunity_ref, :string)
    field(:provider_contact_ref, :string)
    field(:provider_revision, :integer, default: 1)
    field(:idempotency_key, :string)
    field(:lifecycle_state, :string)
    field(:provider_status, :string)
    field(:pass_phase, :string)
    field(:delivery_state, :string)
    field(:delivery_descriptor_document, :map, default: %{})
    field(:spacecraft_id, :string)
    field(:provider_spacecraft_ref, :string)
    field(:source_endpoint_refs, {:array, :string}, default: [])
    field(:path_template_ids, {:array, :string}, default: [])
    field(:starts_at, :utc_datetime_usec)
    field(:ends_at, :utc_datetime_usec)
    field(:request_document, :map, default: %{})
    field(:response_document, :map, default: %{})
    field(:requested_snapshot_document, :map, default: %{})
    field(:provider_confirmed_snapshot_document, :map, default: %{})
    field(:cadence_accepted_snapshot_document, :map, default: %{})
    field(:last_error_document, :map, default: %{})
    field(:operator_review_document, :map, default: %{})
    field(:attempt_count, :integer, default: 0)
    field(:last_reconciled_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :provider_reservation_id,
    :mission_id,
    :provider_id,
    :provider_version,
    :transport_id,
    :transport_version,
    :service_profile_ref,
    :delivery_profile_ref,
    :provider_profile_id,
    :provider_profile_version,
    :scheduled_contact_id,
    :provider_opportunity_ref,
    :provider_revision,
    :idempotency_key,
    :lifecycle_state,
    :spacecraft_id,
    :provider_spacecraft_ref,
    :source_endpoint_refs,
    :path_template_ids,
    :starts_at,
    :ends_at,
    :request_document,
    :response_document,
    :requested_snapshot_document,
    :provider_confirmed_snapshot_document,
    :cadence_accepted_snapshot_document,
    :last_error_document,
    :operator_review_document,
    :delivery_descriptor_document,
    :pass_phase,
    :delivery_state,
    :attempt_count,
    :metadata
  ]

  @spec changeset(ProviderReservation.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderReservation{} = reservation) do
    %__MODULE__{}
    |> cast(domain_attrs(reservation), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:provider_profile_version, greater_than: 0)
    |> validate_number(:provider_version, greater_than: 0)
    |> validate_number(:provider_revision, greater_than: 0)
    |> validate_optional_positive(:provider_account_version)
    |> validate_optional_positive(:provider_account_grant_version)
    |> validate_binding_shape()
    |> validate_number(:transport_version, greater_than: 0)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_length(:idempotency_key, max: 255)
    |> validate_time_range()
    |> unique_constraint(:provider_reservation_id, name: :provider_reservations_pkey)
    |> unique_constraint([:mission_id, :provider_reservation_id],
      name: :provider_reservations_scope_idx
    )
    |> unique_constraint([:mission_id, :provider_profile_id, :idempotency_key],
      name: :provider_reservations_idempotency_idx
    )
    |> unique_constraint([:mission_id, :provider_id, :idempotency_key],
      name: :provider_reservations_provider_idempotency_idx
    )
    |> unique_constraint([:mission_id, :provider_contact_ref],
      name: :provider_reservations_provider_ref_idx
    )
  end

  @spec transition_changeset(struct(), map()) :: Ecto.Changeset.t()
  def transition_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :provider_contact_ref,
      :provider_revision,
      :lifecycle_state,
      :provider_status,
      :pass_phase,
      :delivery_state,
      :delivery_descriptor_document,
      :response_document,
      :provider_confirmed_snapshot_document,
      :cadence_accepted_snapshot_document,
      :last_error_document,
      :attempt_count,
      :last_reconciled_at,
      :metadata
    ])
    |> validate_required([
      :lifecycle_state,
      :provider_revision,
      :response_document,
      :provider_confirmed_snapshot_document,
      :cadence_accepted_snapshot_document,
      :last_error_document,
      :metadata
    ])
    |> validate_number(:provider_revision, greater_than: 0)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:mission_id, :provider_contact_ref],
      name: :provider_reservations_provider_ref_idx
    )
  end

  @spec to_domain(struct()) :: ProviderReservation.t()
  def to_domain(%__MODULE__{} = row) do
    ProviderReservation.new(%{
      provider_reservation_id: row.provider_reservation_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      provider_id: row.provider_id,
      provider_version: row.provider_version,
      provider_account_id: row.provider_account_id,
      provider_account_version: row.provider_account_version,
      provider_account_grant_id: row.provider_account_grant_id,
      provider_account_grant_version: row.provider_account_grant_version,
      transport_id: row.transport_id,
      transport_version: row.transport_version,
      service_profile_ref: JsonDocument.unwrap_value(row.service_profile_ref),
      delivery_profile_ref: JsonDocument.unwrap_value(row.delivery_profile_ref),
      provider_profile_id: row.provider_profile_id,
      provider_profile_version: row.provider_profile_version,
      scheduled_contact_id: row.scheduled_contact_id,
      provider_opportunity_ref: row.provider_opportunity_ref,
      provider_contact_ref: row.provider_contact_ref,
      provider_revision: row.provider_revision,
      idempotency_key: row.idempotency_key,
      lifecycle_state: row.lifecycle_state,
      provider_status: row.provider_status,
      pass_phase: row.pass_phase,
      delivery_state: row.delivery_state,
      delivery_descriptor_document: JsonDocument.unwrap_value(row.delivery_descriptor_document),
      spacecraft_id: row.spacecraft_id,
      provider_spacecraft_ref: row.provider_spacecraft_ref,
      source_endpoint_refs: row.source_endpoint_refs,
      path_template_ids: row.path_template_ids,
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      request_document: JsonDocument.unwrap_value(row.request_document),
      response_document: JsonDocument.unwrap_value(row.response_document),
      requested_snapshot_document: JsonDocument.unwrap_value(row.requested_snapshot_document),
      provider_confirmed_snapshot_document:
        JsonDocument.unwrap_value(row.provider_confirmed_snapshot_document),
      cadence_accepted_snapshot_document:
        JsonDocument.unwrap_value(row.cadence_accepted_snapshot_document),
      last_error_document: JsonDocument.unwrap_value(row.last_error_document),
      operator_review_document: JsonDocument.unwrap_value(row.operator_review_document),
      attempt_count: row.attempt_count,
      last_reconciled_at: row.last_reconciled_at,
      metadata: JsonDocument.unwrap_value(row.metadata),
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp domain_attrs(%ProviderReservation{} = reservation) do
    %{
      provider_reservation_id: reservation.provider_reservation_id,
      organization_id: reservation.organization_id,
      mission_id: reservation.mission_id,
      provider_id: reservation.provider_id,
      provider_version: reservation.provider_version,
      provider_account_id: reservation.provider_account_id,
      provider_account_version: reservation.provider_account_version,
      provider_account_grant_id: reservation.provider_account_grant_id,
      provider_account_grant_version: reservation.provider_account_grant_version,
      transport_id: reservation.transport_id,
      transport_version: reservation.transport_version,
      service_profile_ref: JsonDocument.wrap_value(reservation.service_profile_ref),
      delivery_profile_ref: JsonDocument.wrap_value(reservation.delivery_profile_ref),
      provider_profile_id: reservation.provider_profile_id,
      provider_profile_version: reservation.provider_profile_version,
      scheduled_contact_id: reservation.scheduled_contact_id,
      provider_opportunity_ref: reservation.provider_opportunity_ref,
      provider_contact_ref: reservation.provider_contact_ref,
      provider_revision: reservation.provider_revision,
      idempotency_key: reservation.idempotency_key,
      lifecycle_state: Atom.to_string(reservation.lifecycle_state),
      provider_status: reservation.provider_status,
      pass_phase: Atom.to_string(reservation.pass_phase),
      delivery_state: Atom.to_string(reservation.delivery_state),
      delivery_descriptor_document:
        JsonDocument.wrap_value(reservation.delivery_descriptor_document),
      spacecraft_id: reservation.spacecraft_id,
      provider_spacecraft_ref: reservation.provider_spacecraft_ref,
      source_endpoint_refs: reservation.source_endpoint_refs,
      path_template_ids: reservation.path_template_ids,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      request_document: JsonDocument.wrap_value(reservation.request_document),
      response_document: JsonDocument.wrap_value(reservation.response_document),
      requested_snapshot_document:
        JsonDocument.wrap_value(reservation.requested_snapshot_document),
      provider_confirmed_snapshot_document:
        JsonDocument.wrap_value(reservation.provider_confirmed_snapshot_document),
      cadence_accepted_snapshot_document:
        JsonDocument.wrap_value(reservation.cadence_accepted_snapshot_document),
      last_error_document: JsonDocument.wrap_value(reservation.last_error_document),
      operator_review_document: JsonDocument.wrap_value(reservation.operator_review_document),
      attempt_count: reservation.attempt_count,
      last_reconciled_at: reservation.last_reconciled_at,
      metadata: JsonDocument.wrap_value(reservation.metadata)
    }
  end

  defp all_fields do
    [
      :provider_reservation_id,
      :organization_id,
      :mission_id,
      :provider_id,
      :provider_version,
      :provider_account_id,
      :provider_account_version,
      :provider_account_grant_id,
      :provider_account_grant_version,
      :transport_id,
      :transport_version,
      :service_profile_ref,
      :delivery_profile_ref,
      :provider_profile_id,
      :provider_profile_version,
      :scheduled_contact_id,
      :provider_opportunity_ref,
      :provider_contact_ref,
      :provider_revision,
      :idempotency_key,
      :lifecycle_state,
      :provider_status,
      :pass_phase,
      :delivery_state,
      :delivery_descriptor_document,
      :spacecraft_id,
      :provider_spacecraft_ref,
      :source_endpoint_refs,
      :path_template_ids,
      :starts_at,
      :ends_at,
      :request_document,
      :response_document,
      :requested_snapshot_document,
      :provider_confirmed_snapshot_document,
      :cadence_accepted_snapshot_document,
      :last_error_document,
      :operator_review_document,
      :attempt_count,
      :last_reconciled_at,
      :metadata
    ]
  end

  defp validate_time_range(changeset) do
    case {get_field(changeset, :starts_at), get_field(changeset, :ends_at)} do
      {%DateTime{} = starts_at, %DateTime{} = ends_at} ->
        if DateTime.before?(starts_at, ends_at) do
          changeset
        else
          add_error(changeset, :ends_at, "must be after starts_at")
        end

      _other ->
        changeset
    end
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end

  defp validate_binding_shape(changeset) do
    values =
      Enum.map(
        [
          :provider_account_id,
          :provider_account_version,
          :provider_account_grant_id,
          :provider_account_grant_version
        ],
        &get_field(changeset, &1)
      )

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))) do
      changeset
    else
      add_error(changeset, :provider_account_id, "requires a complete account and grant binding")
    end
  end
end
