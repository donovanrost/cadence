defmodule Cadence.Persistence.Schemas.CommsTransportRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Comms.Transport
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "comms_transports" do
    field(:transport_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:display_name, :string)
    field(:origin, :string, default: "direct")
    field(:transport_kind, :string)
    field(:direction_capability, :string)
    field(:adapter_key, :string)
    field(:configuration, :map, default: %{})
    field(:mission_provider_id, :string)
    field(:mission_provider_version, :integer)
    field(:service_profile_ref, :map)
    field(:delivery_profile_ref, :map)
    field(:provider_configuration_snapshot, :map, default: %{})
    field(:materialized_provider_profile_id, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :transport_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :display_name,
    :origin,
    :transport_kind,
    :direction_capability,
    :adapter_key,
    :configuration,
    :provider_configuration_snapshot,
    :metadata
  ]

  @spec changeset(Transport.t()) :: Ecto.Changeset.t()
  def changeset(%Transport{} = transport) do
    %__MODULE__{}
    |> cast(domain_attrs(transport), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_inclusion(:origin, ["direct", "provider_managed"])
    |> validate_number(:mission_provider_version, greater_than: 0)
    |> unique_constraint([:mission_id, :transport_id, :version],
      name: :comms_transports_scope_idx
    )
  end

  @spec to_domain(struct()) :: Transport.t()
  def to_domain(%__MODULE__{} = row) do
    Transport.new(%{
      transport_id: row.transport_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      display_name: row.display_name,
      origin: row.origin,
      transport_kind: row.transport_kind,
      direction_capability: row.direction_capability,
      adapter_key: row.adapter_key,
      configuration: JsonDocument.unwrap_value(row.configuration),
      mission_provider_id: row.mission_provider_id,
      mission_provider_version: row.mission_provider_version,
      service_profile_ref: JsonDocument.unwrap_value(row.service_profile_ref),
      delivery_profile_ref: JsonDocument.unwrap_value(row.delivery_profile_ref),
      provider_configuration_snapshot:
        JsonDocument.unwrap_value(row.provider_configuration_snapshot),
      materialized_provider_profile_id: row.materialized_provider_profile_id,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Transport{} = transport) do
    %{
      transport_id: transport.transport_id,
      organization_id: transport.organization_id,
      mission_id: transport.mission_id,
      version: transport.version,
      lifecycle_state: Atom.to_string(transport.lifecycle_state),
      display_name: transport.display_name,
      origin: Atom.to_string(transport.origin),
      transport_kind: Atom.to_string(transport.transport_kind),
      direction_capability: Atom.to_string(transport.direction_capability),
      adapter_key: Atom.to_string(transport.adapter_key),
      configuration: JsonDocument.wrap_value(transport.configuration),
      mission_provider_id: transport.mission_provider_id,
      mission_provider_version: transport.mission_provider_version,
      service_profile_ref: maybe_wrap(transport.service_profile_ref),
      delivery_profile_ref: maybe_wrap(transport.delivery_profile_ref),
      provider_configuration_snapshot:
        JsonDocument.wrap_value(transport.provider_configuration_snapshot),
      materialized_provider_profile_id: transport.materialized_provider_profile_id,
      metadata: JsonDocument.wrap_value(transport.metadata)
    }
  end

  defp maybe_wrap(nil), do: nil
  defp maybe_wrap(value), do: JsonDocument.wrap_value(value)

  defp all_fields do
    [
      :transport_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :display_name,
      :origin,
      :transport_kind,
      :direction_capability,
      :adapter_key,
      :configuration,
      :mission_provider_id,
      :mission_provider_version,
      :service_profile_ref,
      :delivery_profile_ref,
      :provider_configuration_snapshot,
      :materialized_provider_profile_id,
      :metadata
    ]
  end
end
