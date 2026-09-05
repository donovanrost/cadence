defmodule CadenceWeb.FederationAuthorityCompositionTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{CatalogRegistry, ReleaseContribution, ReleaseRegistry}
  alias CadenceWeb.ApplicationContributions.OrganizationAdmin

  @canonical_keys ~w(
    organization_admin
    mission_catalog
    spacecraft
    telemetry_decom
    comms
    comms_overview
    ops_console
  )

  test "catalog and release authorities expose each canonical application without duplicate identities" do
    catalog = CatalogRegistry.all()
    releases = ReleaseRegistry.all()

    assert :ok = CatalogRegistry.validate()
    assert :ok = ReleaseRegistry.validate()

    assert Enum.sort(Enum.map(catalog, & &1.definition.application_key)) ==
             Enum.sort(@canonical_keys)

    catalog_surface_ids =
      catalog
      |> Enum.flat_map(fn contribution ->
        Enum.map(contribution.definition.surfaces, fn surface ->
          {contribution.definition.application_key, contribution.definition.version,
           surface.surface_id, surface.version}
        end)
      end)

    release_keys = Enum.map(releases, &ReleaseContribution.key/1)

    assert Enum.uniq(catalog_surface_ids) == catalog_surface_ids
    assert Enum.uniq(release_keys) == release_keys
    assert Enum.sort(release_keys) == Enum.sort(catalog_surface_ids)

    assert length(OrganizationAdmin.surfaces()) == 12
  end
end
