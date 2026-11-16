defmodule Cadence.Applications.SurfaceFixtureApplicationTest do
  @moduledoc """
  The console federation smoke's test-only application is a VALID application in every registry
  once enabled, and absent otherwise (so product registry tests see only product applications).
  """
  # Enabling flips application env that every registry reads: never alongside other tests.
  use ExUnit.Case, async: false

  alias Cadence.Applications.{
    ActionProviderRegistry,
    CatalogRegistry,
    FixtureContributors,
    Registry,
    ReleaseRegistry
  }

  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry, as: SurfaceProviderRegistry
  alias Cadence.TestSupport.SurfaceFixtureApplication

  setup do
    on_exit(&FixtureContributors.disable/0)
    :ok
  end

  test "absent from every registry until enabled" do
    assert FixtureContributors.all() == []
    refute "surface_fixture" in Enum.map(Registry.all(), & &1.application_key)
    assert {:error, _} = ActionProviderRegistry.fetch("surface_fixture")
  end

  test "once enabled, a valid application in every registry" do
    :ok = FixtureContributors.enable()
    assert FixtureContributors.all() == [SurfaceFixtureApplication]

    assert {:ok, definition} = Registry.fetch("surface_fixture", 1)
    assert definition.installable_scopes == [:mission, :spacecraft]
    assert CatalogRegistry.validate() == :ok
    assert "surface_fixture" in Enum.map(CatalogRegistry.all(), & &1.definition.application_key)
    assert ReleaseRegistry.validate() == :ok

    for surface <- ["mission_surface", "spacecraft_surface"] do
      assert {:ok, %{release_id: "surface-fixture-v1"}} =
               ReleaseRegistry.fetch("surface_fixture", 1, surface, 1)
    end

    assert {:ok, SurfaceFixtureApplication.Action} =
             ActionProviderRegistry.fetch("surface_fixture")

    query_ids = Enum.map(SurfaceProviderRegistry.contributions(), & &1.query_id)
    assert "cadence.surface_fixture.mission" in query_ids
    assert "cadence.surface_fixture.spacecraft" in query_ids
  end
end
