defmodule Cadence.Persistence.Schemas.ContactRequirementVersionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactRequirementVersion
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_requirement_version_id, :string, autogenerate: false}

  schema "contact_requirement_versions" do
    field(:contact_requirement_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:spacecraft_id, :string)
    field(:service_direction, :string)
    field(:contact_intent, :string)
    field(:earliest_start, :utc_datetime_usec)
    field(:latest_end, :utc_datetime_usec)
    field(:success_measure, :string)
    field(:minimum_duration_seconds, :integer)
    field(:preferred_duration_seconds, :integer)
    field(:minimum_data_volume_bytes, :integer)
    field(:contact_count, :integer)
    field(:minimum_separation_seconds, :integer)
    field(:priority, :string)
    field(:provider_constraints_document, :map, default: %{})
    field(:station_constraints_document, :map, default: %{})
    field(:policy_constraints_document, :map, default: %{})
    field(:approval_policy_document, :map, default: %{})
    field(:rationale, :string)
    field(:metadata, :map, default: %{})
    field(:content_sha256, :string)
    field(:created_by, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @required_fields [
    :contact_requirement_version_id,
    :contact_requirement_id,
    :organization_id,
    :mission_id,
    :version,
    :spacecraft_id,
    :service_direction,
    :contact_intent,
    :earliest_start,
    :latest_end,
    :success_measure,
    :contact_count,
    :minimum_separation_seconds,
    :priority,
    :provider_constraints_document,
    :station_constraints_document,
    :policy_constraints_document,
    :approval_policy_document,
    :rationale,
    :metadata,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec changeset(ContactRequirementVersion.t()) :: Ecto.Changeset.t()
  def changeset(%ContactRequirementVersion{} = version) do
    %__MODULE__{}
    |> cast(domain_attrs(version), fields())
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_number(:contact_count, greater_than: 0)
    |> validate_number(:minimum_separation_seconds, greater_than_or_equal_to: 0)
    |> validate_optional_positive(:minimum_duration_seconds)
    |> validate_optional_positive(:preferred_duration_seconds)
    |> validate_optional_positive(:minimum_data_volume_bytes)
    |> validate_length(:contact_intent, max: 120)
    |> validate_length(:rationale, max: 2_000)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(
      [:organization_id, :mission_id, :contact_requirement_id, :version],
      name: :contact_requirement_versions_scope_uniq
    )
    |> foreign_key_constraint(:spacecraft_id,
      name: :contact_requirement_versions_spacecraft_fk
    )
  end

  @spec to_domain(struct()) :: ContactRequirementVersion.t()
  def to_domain(%__MODULE__{} = row) do
    ContactRequirementVersion.new(%{
      contact_requirement_version_id: row.contact_requirement_version_id,
      contact_requirement_id: row.contact_requirement_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      spacecraft_id: row.spacecraft_id,
      service_direction: row.service_direction,
      contact_intent: row.contact_intent,
      earliest_start: row.earliest_start,
      latest_end: row.latest_end,
      success_measure: row.success_measure,
      minimum_duration_seconds: row.minimum_duration_seconds,
      preferred_duration_seconds: row.preferred_duration_seconds,
      minimum_data_volume_bytes: row.minimum_data_volume_bytes,
      contact_count: row.contact_count,
      minimum_separation_seconds: row.minimum_separation_seconds,
      priority: row.priority,
      provider_constraints_document: JsonDocument.unwrap_value(row.provider_constraints_document),
      station_constraints_document: JsonDocument.unwrap_value(row.station_constraints_document),
      policy_constraints_document: JsonDocument.unwrap_value(row.policy_constraints_document),
      approval_policy_document: JsonDocument.unwrap_value(row.approval_policy_document),
      rationale: row.rationale,
      metadata: JsonDocument.unwrap_value(row.metadata),
      content_sha256: row.content_sha256,
      created_by: row.created_by,
      created_at: row.created_at
    })
  end

  defp domain_attrs(%ContactRequirementVersion{} = version) do
    %{
      contact_requirement_version_id: version.contact_requirement_version_id,
      contact_requirement_id: version.contact_requirement_id,
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      version: version.version,
      spacecraft_id: version.spacecraft_id,
      service_direction: Atom.to_string(version.service_direction),
      contact_intent: version.contact_intent,
      earliest_start: version.earliest_start,
      latest_end: version.latest_end,
      success_measure: Atom.to_string(version.success_measure),
      minimum_duration_seconds: version.minimum_duration_seconds,
      preferred_duration_seconds: version.preferred_duration_seconds,
      minimum_data_volume_bytes: version.minimum_data_volume_bytes,
      contact_count: version.contact_count,
      minimum_separation_seconds: version.minimum_separation_seconds,
      priority: Atom.to_string(version.priority),
      provider_constraints_document:
        JsonDocument.wrap_value(version.provider_constraints_document),
      station_constraints_document: JsonDocument.wrap_value(version.station_constraints_document),
      policy_constraints_document: JsonDocument.wrap_value(version.policy_constraints_document),
      approval_policy_document: JsonDocument.wrap_value(version.approval_policy_document),
      rationale: version.rationale,
      metadata: JsonDocument.wrap_value(version.metadata),
      content_sha256: version.content_sha256,
      created_by: version.created_by,
      created_at: version.created_at
    }
  end

  defp fields do
    @required_fields ++
      [
        :minimum_duration_seconds,
        :preferred_duration_seconds,
        :minimum_data_volume_bytes
      ]
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end
end
