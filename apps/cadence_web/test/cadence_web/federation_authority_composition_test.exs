defmodule CadenceWeb.FederationAuthorityCompositionTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{CatalogRegistry, ReleaseContribution, ReleaseRegistry}
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry, as: SurfaceProviderRegistry

  # Telemetry Decom is headless (#669): it is in the catalog with no surfaces and no release.
  @provider_ledger [
    Cadence.Applications.OpsConsole
  ]

  @canonical_keys ~w(
    telemetry_decom
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

    # The ops-console remote exposes only its own application (#669 retired ./Limits and
    # ./DerivedTelemetry).
    assert releases
           |> Enum.filter(&(&1.remote_name == "cadence_ops_console"))
           |> Enum.map(& &1.exposed_module)
           |> Enum.uniq() == ["./Application"]
  end

  test "composes the exact core and optional web query contribution ledger" do
    contributions = SurfaceProviderRegistry.contributions()
    provider_ledger = Enum.flat_map(@provider_ledger, & &1.surface_query_contributions())

    assert length(contributions) == length(provider_ledger)

    assert Enum.sort(Enum.map(contributions, &contribution_identity/1)) ==
             Enum.sort(Enum.map(provider_ledger, &contribution_identity/1))

    assert contributions
           |> Enum.frequencies_by(& &1.application_key) == %{
             "ops_console" => 7
           }
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
