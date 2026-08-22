defmodule Cadence.Applications.PacketBindings.ConfigurationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.PacketBindingConfiguration
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:packet_binding_configuration_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "application_packet_binding_configurations" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:application_installation_id, :string)
    field(:application_key, :string)
    field(:application_version, :integer)
    field(:capability_family_key, :string)
    field(:input_id, :string)
    field(:input_version, :integer)
    field(:configuration_version, :integer, default: 1)
    field(:enabled, :boolean, default: true)
    field(:applied_binding_set_id, :string)
    field(:applied_binding_set_version, :integer)
    field(:applied_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :packet_binding_configuration_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :application_installation_id,
    :application_key,
    :application_version,
    :capability_family_key,
    :input_id,
    :input_version,
    :configuration_version,
    :enabled,
    :applied_binding_set_id,
    :applied_binding_set_version,
    :applied_at,
    :metadata
  ]

  @required_fields [
    :packet_binding_configuration_id,
    :mission_id,
    :application_installation_id,
    :application_key,
    :application_version,
    :capability_family_key,
    :input_id,
    :input_version,
    :configuration_version,
    :metadata
  ]

  @spec changeset(struct(), PacketBindingConfiguration.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %PacketBindingConfiguration{} = configuration) do
    row
    |> cast(domain_attrs(configuration), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:application_version, greater_than: 0)
    |> validate_number(:input_version, greater_than: 0)
    |> validate_number(:configuration_version, greater_than: 0)
    |> unique_constraint([:application_installation_id, :input_id, :input_version],
      name: :application_packet_binding_configurations_input_idx
    )
  end

  defp domain_attrs(%PacketBindingConfiguration{} = configuration) do
    %{
      packet_binding_configuration_id: configuration.packet_binding_configuration_id,
      organization_id: configuration.organization_id,
      mission_id: configuration.mission_id,
      spacecraft_id: configuration.spacecraft_id,
      application_installation_id: configuration.application_installation_id,
      application_key: configuration.application_key,
      application_version: configuration.application_version,
      capability_family_key: Atom.to_string(configuration.capability_family_key),
      input_id: configuration.input_id,
      input_version: configuration.input_version,
      configuration_version: configuration.configuration_version,
      enabled: configuration.enabled,
      applied_binding_set_id: configuration.applied_binding_set_id,
      applied_binding_set_version: configuration.applied_binding_set_version,
      applied_at: configuration.applied_at,
      metadata: JsonDocument.wrap_value(configuration.metadata)
    }
  end
end
