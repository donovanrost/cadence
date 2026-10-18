defmodule CadenceWeb.FederationAuthorityCompositionTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{CatalogRegistry, ReleaseContribution, ReleaseRegistry}
  alias Cadence.Applications.OrganizationAdmin
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry, as: SurfaceProviderRegistry

  @provider_ledger [
    Cadence.Applications.Comms,
    Cadence.Applications.Spacecraft,
    Cadence.Applications.MissionCatalog,
    Cadence.Applications.TelemetryDecom,
    Cadence.Applications.DerivedTelemetry,
    Cadence.Applications.Limits,
    Cadence.Applications.OpsConsole,
    OrganizationAdmin
  ]

  @canonical_keys ~w(
    organization_admin
    mission_catalog
    spacecraft
    telemetry_decom
    derived_telemetry
    limits
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

    assert [
             %ReleaseContribution{
               application_version: 1,
               surface_id: "manage",
               surface_version: 1,
               remote_name: "cadence_ops_console",
               exposed_module: "./DerivedTelemetry"
             }
           ] = Enum.filter(releases, &(&1.application_key == "derived_telemetry"))

    assert length(OrganizationAdmin.surfaces()) == 12
  end

  test "composes the exact core and optional web query contribution ledger" do
    contributions = SurfaceProviderRegistry.contributions()
    provider_ledger = Enum.flat_map(@provider_ledger, & &1.surface_query_contributions())

    assert length(contributions) == length(provider_ledger)

    assert Enum.sort(Enum.map(contributions, &contribution_identity/1)) ==
             Enum.sort(Enum.map(provider_ledger, &contribution_identity/1))

    assert contributions
           |> Enum.frequencies_by(& &1.application_key) == %{
             "comms" => 15,
             "spacecraft" => 11,
             "mission_catalog" => 10,
             "telemetry_decom" => 2,
             "derived_telemetry" => 1,
             "limits" => 2,
             "ops_console" => 35,
             "organization_admin" => 12
           }

    assert Enum.count(contributions, &(&1.application_key == "organization_admin")) == 12
  end

  defp contribution_identity(contribution) do
    {
      contribution.application_key,
      contribution.application_version,
      contribution.query_id,
      contribution.query_version,
      contribution.provider
    }
  end
end
