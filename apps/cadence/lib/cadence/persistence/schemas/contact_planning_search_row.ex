defmodule Cadence.Persistence.Schemas.ContactPlanningSearchRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactPlanningSearch
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_planning_search_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_planning_searches" do
    field(:contact_planning_run_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:route_key, :string)
    field(:route_order, :integer)
    field(:provider_id, :string)
    field(:provider_version, :integer)
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:provider_account_grant_id, :string)
    field(:provider_account_grant_version, :integer)
    field(:provider_display_name, :string)
    field(:outcome, :string)
    field(:opportunity_count, :integer)
    field(:route_binding_document, :map, default: %{})
    field(:readiness_document, :map, default: %{})
    field(:error_document, :map, default: %{})
    field(:content_sha256, :string)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :contact_planning_search_id,
    :contact_planning_run_id,
    :organization_id,
    :mission_id,
    :route_key,
    :route_order,
    :outcome,
    :opportunity_count,
    :route_binding_document,
    :readiness_document,
    :error_document,
    :content_sha256,
    :started_at,
    :completed_at
  ]

  @optional_fields [
    :provider_id,
    :provider_version,
    :provider_account_id,
    :provider_account_version,
    :provider_account_grant_id,
    :provider_account_grant_version,
    :provider_display_name
  ]

  @spec changeset(ContactPlanningSearch.t()) :: Ecto.Changeset.t()
  def changeset(%ContactPlanningSearch{} = search) do
    %__MODULE__{}
    |> cast(domain_attrs(search), @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:route_order, greater_than_or_equal_to: 0)
    |> validate_number(:opportunity_count, greater_than_or_equal_to: 0)
    |> validate_optional_positive(:provider_version)
    |> validate_optional_positive(:provider_account_version)
    |> validate_optional_positive(:provider_account_grant_version)
    |> validate_inclusion(:outcome, Enum.map(ContactPlanningSearch.outcomes(), &to_string/1))
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint([:contact_planning_run_id, :route_key],
      name: :contact_planning_searches_route_idx
    )
    |> foreign_key_constraint(:contact_planning_run_id,
      name: :contact_planning_searches_run_fk
    )
  end

  @spec to_domain(struct()) :: ContactPlanningSearch.t()
  def to_domain(%__MODULE__{} = row) do
    ContactPlanningSearch.new(%{
      contact_planning_search_id: row.contact_planning_search_id,
      contact_planning_run_id: row.contact_planning_run_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      route_key: row.route_key,
      route_order: row.route_order,
      provider_id: row.provider_id,
      provider_version: row.provider_version,
      provider_account_id: row.provider_account_id,
      provider_account_version: row.provider_account_version,
      provider_account_grant_id: row.provider_account_grant_id,
      provider_account_grant_version: row.provider_account_grant_version,
      provider_display_name: row.provider_display_name,
      outcome: row.outcome,
      opportunity_count: row.opportunity_count,
      route_binding_document: JsonDocument.unwrap_value(row.route_binding_document),
      readiness_document: JsonDocument.unwrap_value(row.readiness_document),
      error_document: JsonDocument.unwrap_value(row.error_document),
      content_sha256: row.content_sha256,
      started_at: row.started_at,
      completed_at: row.completed_at,
      inserted_at: row.inserted_at
    })
  end

  defp domain_attrs(search) do
    %{
      contact_planning_search_id: search.contact_planning_search_id,
      contact_planning_run_id: search.contact_planning_run_id,
      organization_id: search.organization_id,
      mission_id: search.mission_id,
      route_key: search.route_key,
      route_order: search.route_order,
      provider_id: search.provider_id,
      provider_version: search.provider_version,
      provider_account_id: search.provider_account_id,
      provider_account_version: search.provider_account_version,
      provider_account_grant_id: search.provider_account_grant_id,
      provider_account_grant_version: search.provider_account_grant_version,
      provider_display_name: search.provider_display_name,
      outcome: Atom.to_string(search.outcome),
      opportunity_count: search.opportunity_count,
      route_binding_document: JsonDocument.wrap_value(search.route_binding_document),
      readiness_document: JsonDocument.wrap_value(search.readiness_document),
      error_document: JsonDocument.wrap_value(search.error_document),
      content_sha256: search.content_sha256,
      started_at: search.started_at,
      completed_at: search.completed_at
    }
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end
end
