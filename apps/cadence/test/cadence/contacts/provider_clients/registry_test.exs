defmodule Cadence.Contacts.ProviderClients.RegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ProviderClients.{Definition, Registry, SimulatorHTTP}
  alias Cadence.Extensions.Presentation.ConfigurationDefinition
  alias Cadence.GroundNetworks.ProviderContext

  test "publishes a typed provider connector and resolves its runtime client" do
    assert [{"Ground Network Simulator", "simulator"}] = Registry.form_options()
    assert %Definition{} = definition = Registry.default_definition()
    assert definition.version == 1
    assert definition.provider_type == :simulator
    assert definition.client_key == :simulator_http
    assert definition.module == SimulatorHTTP
    assert %ConfigurationDefinition{} = definition.configuration

    assert [section] = definition.configuration.sections
    assert section.id == "provider-account-control-plane-section"

    assert Enum.map(section.fields, & &1.field) == [
             :base_url,
             :region_ref,
             :environment_ref,
             :event_ingestion_mode
           ]

    assert {:ok, ^definition} = Registry.fetch_definition("simulator")
    assert {:ok, ^definition} = Registry.fetch_definition(:simulator)
    assert :ok = Definition.validate(definition)

    assert {:error, {:unsupported_provider_connector_version, "simulator", 2}} =
             Registry.fetch_definition("simulator", 2)

    assert {:ok, SimulatorHTTP} =
             Registry.fetch(%ProviderContext{client_key: "simulator_http"})

    assert {:error, {:unknown_provider_connector, "invented"}} =
             Registry.fetch_definition("invented")
  end
end
