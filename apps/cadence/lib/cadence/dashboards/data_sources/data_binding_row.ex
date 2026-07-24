defmodule Cadence.Dashboards.DataSources.DataBindingRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.DataBinding
  alias Cadence.Management.DataSources.ExecutionPolicy
  alias Cadence.Persistence.JsonDocument

  @primary_key {:binding_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_data_bindings" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:realm, :string)
    field(:logical_source, :string)
    field(:data_source_id, :string)
    field(:dataset, :string)
    field(:priority, :integer, default: 0)
    field(:status, :string, default: "active")
    field(:binding_version, :integer, default: 1)
    field(:current_event_id, :string)
    field(:active_from, :utc_datetime_usec)
    field(:active_to, :utc_datetime_usec)
    field(:disabled_at, :utc_datetime_usec)
    field(:superseded_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :binding_id,
    :organization_id,
    :mission_id,
    :realm,
    :logical_source,
    :data_source_id,
    :dataset,
    :priority,
    :status,
    :binding_version,
    :current_event_id,
    :active_from,
    :active_to,
    :disabled_at,
    :superseded_at,
    :metadata
  ]

  @required_fields [
    :binding_id,
    :realm,
    :logical_source,
    :data_source_id,
    :priority,
    :status,
    :binding_version,
    :metadata
  ]

  @statuses ["active", "disabled", "superseded"]

  @spec changeset(DataBinding.t()) :: Ecto.Changeset.t()
  def changeset(%DataBinding{} = data_binding), do: changeset(%__MODULE__{}, data_binding)

  @spec changeset(struct(), DataBinding.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %DataBinding{} = data_binding) do
    row
    |> cast(domain_attrs(data_binding), @fields)
    |> validate_required(@required_fields)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_number(:binding_version, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_dashboard_policy_metadata()
    |> foreign_key_constraint(:data_source_id, name: :dashboard_data_bindings_data_source_fk)
    |> foreign_key_constraint(:organization_id, name: :dashboard_data_bindings_org_fk)
    |> foreign_key_constraint(:mission_id, name: :dashboard_data_bindings_org_mission_fk)
  end

  @spec to_domain(struct()) :: DataBinding.t()
  def to_domain(%__MODULE__{} = row) do
    %DataBinding{
      binding_id: row.binding_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      realm: known_atom(row.realm),
      logical_source: known_atom(row.logical_source),
      data_source_id: row.data_source_id,
      dataset: row.dataset,
      priority: row.priority,
      status: known_atom(row.status),
      binding_version: row.binding_version,
      current_event_id: row.current_event_id,
      active_from: row.active_from,
      active_to: row.active_to,
      disabled_at: row.disabled_at,
      superseded_at: row.superseded_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%DataBinding{} = data_binding) do
    %{
      binding_id: data_binding.binding_id,
      organization_id: data_binding.organization_id,
      mission_id: data_binding.mission_id,
      realm: enum_string(data_binding.realm),
      logical_source: enum_string(data_binding.logical_source),
      data_source_id: data_binding.data_source_id,
      dataset: data_binding.dataset,
      priority: data_binding.priority,
      status: enum_string(data_binding.status),
      binding_version: data_binding.binding_version,
      current_event_id: data_binding.current_event_id,
      active_from: data_binding.active_from,
      active_to: data_binding.active_to,
      disabled_at: data_binding.disabled_at,
      superseded_at: data_binding.superseded_at,
      metadata: JsonDocument.wrap_value(data_binding.metadata)
    }
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp known_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp known_atom(value), do: value

  defp validate_dashboard_policy_metadata(changeset) do
    changeset
    |> get_field(:metadata)
    |> JsonDocument.unwrap_value()
    |> ExecutionPolicy.validate_metadata()
    |> case do
      :ok -> changeset
      {:error, errors} -> Enum.reduce(errors, changeset, &add_error(&2, :metadata, &1))
    end
  end
end
