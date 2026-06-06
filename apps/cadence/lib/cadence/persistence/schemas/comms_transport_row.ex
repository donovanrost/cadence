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
    field(:transport_kind, :string)
    field(:direction_capability, :string)
    field(:adapter_key, :string)
    field(:configuration, :map, default: %{})
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
    :transport_kind,
    :direction_capability,
    :adapter_key,
    :configuration,
    :metadata
  ]

  @spec changeset(Transport.t()) :: Ecto.Changeset.t()
  def changeset(%Transport{} = transport) do
    %__MODULE__{}
    |> cast(domain_attrs(transport), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:display_name, min: 1, max: 200)
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
      transport_kind: row.transport_kind,
      direction_capability: row.direction_capability,
      adapter_key: row.adapter_key,
      configuration: JsonDocument.unwrap_value(row.configuration),
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
      transport_kind: Atom.to_string(transport.transport_kind),
      direction_capability: Atom.to_string(transport.direction_capability),
      adapter_key: Atom.to_string(transport.adapter_key),
      configuration: JsonDocument.wrap_value(transport.configuration),
      materialized_provider_profile_id: transport.materialized_provider_profile_id,
      metadata: JsonDocument.wrap_value(transport.metadata)
    }
  end

  defp all_fields do
    [
      :transport_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :display_name,
      :transport_kind,
      :direction_capability,
      :adapter_key,
      :configuration,
      :materialized_provider_profile_id,
      :metadata
    ]
  end
end
