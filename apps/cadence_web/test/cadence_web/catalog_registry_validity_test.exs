defmodule CadenceWeb.CatalogRegistryValidityTest do
  @moduledoc """
  One invalid contributor empties the whole application-host catalog: `CatalogRegistry.all/0`
  returns `[]` and `validate/0` fails when any definition is invalid, so every federated surface
  goes at once. Legacy deletions (DECISIONS #79) remove surfaces, and an application left with an
  installable scope it has no workspace surface for is invalid. L13 + §11c A did exactly that to
  organization_admin (11-15): each batch alone was valid, the two together weren't. This names the
  contributor instead of failing as an empty catalog.
  """
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ApplicationDefinition,
    CatalogRegistry,
    Comms,
    DerivedTelemetry,
    LegacyCommsOverview,
    Limits,
    MissionCatalog,
    OpsConsole,
    OrganizationAdmin,
    Spacecraft,
    TelemetryDecomCatalogContribution
  }

  @contributors [
    Comms,
    LegacyCommsOverview,
    Limits,
    MissionCatalog,
    Spacecraft,
    TelemetryDecomCatalogContribution,
    OpsConsole,
    DerivedTelemetry,
    OrganizationAdmin
  ]

  test "every contributed application definition is valid on its own" do
    for contributor <- @contributors,
        contribution <- contributor.catalog_contributions() do
      definition = contribution.definition

      assert ApplicationDefinition.validate(definition) == :ok,
             "#{definition.application_key}'s definition is invalid (installable scopes " <>
               "#{inspect(definition.installable_scopes)}, surfaces " <>
               "#{inspect(Enum.map(definition.surfaces, &{&1.surface_id, &1.scope}))}); " <>
               "it would empty the whole application-host catalog"
    end
  end

  test "the registry validates and lists every contributor, organization_admin included" do
    assert CatalogRegistry.validate() == :ok

    keys = Enum.map(CatalogRegistry.all(), & &1.definition.application_key)

    assert keys != []
    assert "organization_admin" in keys
    assert {:ok, _contribution} = CatalogRegistry.fetch("organization_admin")
  end
end
