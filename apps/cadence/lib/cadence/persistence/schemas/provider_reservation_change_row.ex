defmodule Cadence.Persistence.Schemas.ProviderReservationChangeRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ProviderReservationChange
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:provider_reservation_change_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "provider_reservation_changes" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_reservation_id, :string)
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:provider_revision, :integer)
    field(:from_provider_revision, :integer)
    field(:change_identity, :string)
    field(:proposal_hash, :string)
    field(:before_snapshot_document, :map)
    field(:after_snapshot_document, :map)
    field(:changed_fields_document, :map)
    field(:classification, :string)
    field(:lifecycle_state, :string)
    field(:policy_version, :integer)
    field(:policy_document, :map)
    field(:decision_document, :map)
    field(:actionable, :boolean, default: false)
    field(:already_effective, :boolean, default: false)
    field(:deadline_at, :utc_datetime_usec)
    field(:provider_evidence_id, :string)
    field(:decided_at, :utc_datetime_usec)
    field(:decided_by, :string)
    timestamps()
  end

  @fields ~w(
    provider_reservation_change_id organization_id mission_id provider_reservation_id
    provider_account_id provider_account_version provider_revision from_provider_revision
    change_identity proposal_hash before_snapshot_document after_snapshot_document
    changed_fields_document classification lifecycle_state policy_version policy_document
    decision_document actionable already_effective deadline_at provider_evidence_id decided_at
    decided_by inserted_at updated_at
  )a
  @required @fields --
              ~w(provider_account_id provider_account_version deadline_at provider_evidence_id decided_at decided_by inserted_at updated_at)a

  def changeset(%ProviderReservationChange{} = change) do
    %__MODULE__{}
    |> cast(attrs(change), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required)
    |> validate_number(:provider_revision, greater_than: 0)
    |> validate_number(:from_provider_revision, greater_than: 0)
    |> validate_number(:policy_version, greater_than: 0)
    |> unique_constraint([:provider_reservation_id, :change_identity],
      name: :provider_reservation_changes_identity_idx
    )
  end

  def decision_changeset(%__MODULE__{} = row, attrs) do
    cast(row, attrs, [:lifecycle_state, :decision_document, :decided_at, :decided_by])
  end

  def to_domain(%__MODULE__{} = row) do
    row
    |> Map.from_struct()
    |> Map.take(@fields)
    |> unwrap_documents()
    |> ProviderReservationChange.new()
  end

  defp attrs(change) do
    change
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.update!(:classification, &Atom.to_string/1)
    |> Map.update!(:lifecycle_state, &Atom.to_string/1)
    |> wrap_documents()
  end

  defp wrap_documents(attrs) do
    Enum.reduce(document_fields(), attrs, fn field, acc ->
      Map.update!(acc, field, &JsonDocument.wrap_value/1)
    end)
  end

  defp unwrap_documents(attrs) do
    Enum.reduce(document_fields(), attrs, fn field, acc ->
      Map.update!(acc, field, &JsonDocument.unwrap_value/1)
    end)
  end

  defp document_fields,
    do:
      ~w(before_snapshot_document after_snapshot_document changed_fields_document policy_document decision_document)a
end
