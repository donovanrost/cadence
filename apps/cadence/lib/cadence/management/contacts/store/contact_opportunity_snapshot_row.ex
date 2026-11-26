defmodule Cadence.Management.Contacts.Store.ContactOpportunitySnapshotRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactOpportunitySnapshot
  alias Cadence.Management.Contacts.Store.ContactPlanningSearchRow
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
    field(:normalized_opportunity_document, :map, default: %{})
    field(:evaluation_document, :map, default: %{})
    field(:eligible, :boolean)
    field(:content_sha256, :string)
    field(:captured_at, :utc_datetime_usec)

    belongs_to(:search, ContactPlanningSearchRow,
      type: :string,
      foreign_key: :contact_planning_search_id,
      references: :contact_planning_search_id,
      define_field: false
    )

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
    :normalized_opportunity_document,
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
  def to_domain(%__MODULE__{search: %ContactPlanningSearchRow{} = search} = row) do
    binding = JsonDocument.unwrap_value(search.route_binding_document)
    readiness = JsonDocument.unwrap_value(search.readiness_document)
    to_domain(row, binding, readiness)
  end

  @doc false
  def to_domain(%__MODULE__{} = row, route_binding, readiness \\ %{}) do
    opportunity =
      expand_opportunity(row.normalized_opportunity_document, route_binding, readiness)

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
      route_binding_document: route_binding,
      normalized_opportunity_document: opportunity,
      provider_evidence_document: opportunity,
      evaluation_document: JsonDocument.unwrap_value(row.evaluation_document),
      eligible: row.eligible,
      content_sha256: row.content_sha256,
      captured_at: row.captured_at,
      inserted_at: row.inserted_at
    })
  end

  @doc false
  def domain_attrs(snapshot) do
    domain_attrs(snapshot, JsonDocument.wrap_value(snapshot.normalized_opportunity_document))
  end

  defp domain_attrs(snapshot, encoded_opportunity) do
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
      normalized_opportunity_document: encoded_opportunity,
      evaluation_document: JsonDocument.wrap_value(snapshot.evaluation_document),
      eligible: snapshot.eligible,
      content_sha256: snapshot.content_sha256,
      captured_at: snapshot.captured_at
    }
  end

  @doc false
  def compact_attrs(snapshot, readiness) do
    domain_attrs(snapshot, compact_opportunity(snapshot, readiness))
  end

  defp compact_opportunity(snapshot, readiness) do
    document = snapshot.normalized_opportunity_document
    binding = snapshot.route_binding_document
    delivery_ref = get_in(binding, ["delivery_profile_ref", "id"])
    route_key = binding["route_key"]

    shared_route? =
      is_binary(route_key) and is_binary(delivery_ref) and
        document["route_key"] == route_key and document["delivery_profile_ref"] == delivery_ref

    orbit = get_in(document, ["extensions", "orbit_readiness"])
    shared_orbit? = is_map(orbit) and orbit == readiness["orbit_readiness"]

    document =
      if shared_route?,
        do: Map.drop(document, ["route_key", "delivery_profile_ref"]),
        else: document

    document =
      if shared_orbit?,
        do: update_in(document, ["extensions"], &Map.delete(&1, "orbit_readiness")),
        else: document

    %{"value" => document, "shared_route" => shared_route?, "shared_orbit" => shared_orbit?}
  end

  defp expand_opportunity(stored, binding, readiness) do
    document = JsonDocument.unwrap_value(stored)

    document =
      if stored["shared_route"] do
        Map.merge(document, %{
          "route_key" => binding["route_key"],
          "delivery_profile_ref" => get_in(binding, ["delivery_profile_ref", "id"])
        })
      else
        document
      end

    if stored["shared_orbit"],
      do: put_in(document, ["extensions", "orbit_readiness"], readiness["orbit_readiness"]),
      else: document
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
