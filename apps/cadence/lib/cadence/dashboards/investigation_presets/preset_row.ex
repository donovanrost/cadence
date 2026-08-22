defmodule Cadence.Dashboards.InvestigationPresets.PresetRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.InvestigationPreset
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:dashboard_investigation_preset_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_investigation_presets" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:name, :string)
    field(:description, :string)
    field(:schema, :string)
    field(:preset_kind, :string)
    field(:runtime_query, :map, default: %{})
    field(:payload, :map, default: %{})
    field(:primary_data_view, :string)
    field(:compare_data_view, :string)
    field(:affected_placement_ids, {:array, :string}, default: [])
    field(:created_by, :string)
    field(:updated_by, :string)

    timestamps()
  end

  @fields [
    :dashboard_investigation_preset_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :name,
    :description,
    :schema,
    :preset_kind,
    :runtime_query,
    :payload,
    :primary_data_view,
    :compare_data_view,
    :affected_placement_ids,
    :created_by,
    :updated_by
  ]

  @required_fields [
    :dashboard_investigation_preset_id,
    :mission_id,
    :dashboard_id,
    :name,
    :schema,
    :preset_kind,
    :runtime_query,
    :payload
  ]

  @spec changeset(InvestigationPreset.t()) :: Ecto.Changeset.t()
  def changeset(%InvestigationPreset{} = preset) do
    %__MODULE__{}
    |> cast(attrs(preset), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:preset_kind, ["comparison"])
    |> validate_map(:runtime_query)
    |> validate_map(:payload)
    |> unique_constraint([:dashboard_investigation_preset_id],
      name: :dashboard_investigation_presets_pkey
    )
    |> unique_constraint(:name, name: :dashboard_investigation_presets_dashboard_name_idx)
  end

  @spec to_domain(%__MODULE__{}) :: InvestigationPreset.t()
  def to_domain(%__MODULE__{} = row) do
    InvestigationPreset.new(%{
      dashboard_investigation_preset_id: row.dashboard_investigation_preset_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      dashboard_id: row.dashboard_id,
      name: row.name,
      description: row.description,
      schema: row.schema,
      preset_kind: row.preset_kind,
      runtime_query: row.runtime_query || %{},
      payload: row.payload || %{},
      primary_data_view: row.primary_data_view,
      compare_data_view: row.compare_data_view,
      affected_placement_ids: row.affected_placement_ids || [],
      created_by: row.created_by,
      updated_by: row.updated_by,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp attrs(%InvestigationPreset{} = preset) do
    %{
      dashboard_investigation_preset_id: preset.dashboard_investigation_preset_id,
      organization_id: preset.organization_id,
      mission_id: preset.mission_id,
      dashboard_id: preset.dashboard_id,
      name: preset.name,
      description: preset.description,
      schema: preset.schema,
      preset_kind: Atom.to_string(preset.preset_kind),
      runtime_query: JsonDocument.encode(preset.runtime_query),
      payload: JsonDocument.encode(preset.payload),
      primary_data_view: preset.primary_data_view,
      compare_data_view: preset.compare_data_view,
      affected_placement_ids: preset.affected_placement_ids,
      created_by: preset.created_by,
      updated_by: preset.updated_by
    }
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _value -> add_error(changeset, field, "must be a map")
    end
  end
end
