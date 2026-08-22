defmodule Cadence.Management.Contacts.Store.ContactOpportunitySnapshotRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactOpportunitySnapshot
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_opportunity_snapshot_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_opportunity_snapshots" do
    field(:contact_planning_run_id, :string)
    field(:contact_planning_search_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_requirement_id, :string)
    field(:contact_requirement_version, :integer)
    field(:provider_opportunity_ref, :string)
    field(:starts_at, :utc_datetime_usec)
    field(:ends_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:availability, :string)
    field(:estimated_capacity_document, :map, default: %{})
    field(:synthetic, :boolean)
    field(:route_binding_document, :map, default: %{})
    field(:normalized_opportunity_document, :map, default: %{})
    field(:provider_evidence_document, :map, default: %{})
    field(:evaluation_document, :map, default: %{})
    field(:eligible, :boolean)
    field(:content_sha256, :string)
    field(:captured_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :contact_opportunity_snapshot_id,
    :contact_planning_run_id,
    :contact_planning_search_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :provider_opportunity_ref,
    :starts_at,
    :ends_at,
    :expires_at,
    :availability,
    :estimated_capacity_document,
    :synthetic,
    :route_binding_document,
    :normalized_opportunity_document,
    :provider_evidence_document,
    :evaluation_document,
    :eligible,
    :content_sha256,
    :captured_at
  ]

  @spec changeset(ContactOpportunitySnapshot.t()) :: Ecto.Changeset.t()
  def changeset(%ContactOpportunitySnapshot{} = snapshot) do
    %__MODULE__{}
    |> cast(domain_attrs(snapshot), @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:contact_requirement_version, greater_than: 0)
    |> validate_inclusion(:availability, ~w(available limited unavailable))
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_time_range()
    |> unique_constraint(
      [:contact_planning_search_id, :provider_opportunity_ref, :content_sha256],
      name: :contact_opportunity_snapshots_content_idx
    )
    |> foreign_key_constraint(:contact_planning_run_id,
      name: :contact_opportunity_snapshots_run_fk
    )
    |> foreign_key_constraint(:contact_planning_search_id,
      name: :contact_opportunity_snapshots_search_fk
    )
    |> foreign_key_constraint(:contact_requirement_version,
      name: :contact_opportunity_snapshots_requirement_version_fk
    )
  end

  @spec to_domain(struct()) :: ContactOpportunitySnapshot.t()
  def to_domain(%__MODULE__{} = row) do
    ContactOpportunitySnapshot.new(%{
      contact_opportunity_snapshot_id: row.contact_opportunity_snapshot_id,
      contact_planning_run_id: row.contact_planning_run_id,
      contact_planning_search_id: row.contact_planning_search_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_requirement_id: row.contact_requirement_id,
      contact_requirement_version: row.contact_requirement_version,
      provider_opportunity_ref: row.provider_opportunity_ref,
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      expires_at: row.expires_at,
      availability: row.availability,
      estimated_capacity_document: JsonDocument.unwrap_value(row.estimated_capacity_document),
      synthetic: row.synthetic,
      route_binding_document: JsonDocument.unwrap_value(row.route_binding_document),
      normalized_opportunity_document:
        JsonDocument.unwrap_value(row.normalized_opportunity_document),
      provider_evidence_document: JsonDocument.unwrap_value(row.provider_evidence_document),
      evaluation_document: JsonDocument.unwrap_value(row.evaluation_document),
      eligible: row.eligible,
      content_sha256: row.content_sha256,
      captured_at: row.captured_at,
      inserted_at: row.inserted_at
    })
  end

  defp domain_attrs(snapshot) do
    %{
      contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id,
      contact_planning_run_id: snapshot.contact_planning_run_id,
      contact_planning_search_id: snapshot.contact_planning_search_id,
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      contact_requirement_id: snapshot.contact_requirement_id,
      contact_requirement_version: snapshot.contact_requirement_version,
      provider_opportunity_ref: snapshot.provider_opportunity_ref,
      starts_at: snapshot.starts_at,
      ends_at: snapshot.ends_at,
      expires_at: snapshot.expires_at,
      availability: Atom.to_string(snapshot.availability),
      estimated_capacity_document: JsonDocument.wrap_value(snapshot.estimated_capacity_document),
      synthetic: snapshot.synthetic,
      route_binding_document: JsonDocument.wrap_value(snapshot.route_binding_document),
      normalized_opportunity_document:
        JsonDocument.wrap_value(snapshot.normalized_opportunity_document),
      provider_evidence_document: JsonDocument.wrap_value(snapshot.provider_evidence_document),
      evaluation_document: JsonDocument.wrap_value(snapshot.evaluation_document),
      eligible: snapshot.eligible,
      content_sha256: snapshot.content_sha256,
      captured_at: snapshot.captured_at
    }
  end

  defp validate_time_range(changeset) do
    case {get_field(changeset, :starts_at), get_field(changeset, :ends_at)} do
      {%DateTime{} = starts_at, %DateTime{} = ends_at} ->
        if DateTime.before?(starts_at, ends_at),
          do: changeset,
          else: add_error(changeset, :ends_at, "must be after starts_at")

      _other ->
        changeset
    end
  end
end
