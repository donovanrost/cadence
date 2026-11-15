defmodule Cadence.Applications.ContractProbeApplicationTest do
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
  alias Cadence.TestSupport.ContractProbeApplication

  setup do
    on_exit(&FixtureContributors.disable/0)
    :ok
  end

  test "absent from every registry until enabled" do
    assert FixtureContributors.all() == []
    refute "contract_probe" in Enum.map(Registry.all(), & &1.application_key)
    assert {:error, _} = ActionProviderRegistry.fetch("contract_probe")
  end

  test "once enabled, a valid application in every registry" do
    :ok = FixtureContributors.enable()
    assert FixtureContributors.all() == [ContractProbeApplication]

    assert {:ok, definition} = Registry.fetch("contract_probe", 1)
    assert definition.installable_scopes == [:mission, :spacecraft]
    assert CatalogRegistry.validate() == :ok
    assert "contract_probe" in Enum.map(CatalogRegistry.all(), & &1.definition.application_key)
    assert ReleaseRegistry.validate() == :ok

    for surface <- ["mission_contracts", "runtime_contracts"] do
      assert {:ok, %{release_id: "contract-probe-v1"}} =
               ReleaseRegistry.fetch("contract_probe", 1, surface, 1)
    end

    assert {:ok, ContractProbeApplication.Action} = ActionProviderRegistry.fetch("contract_probe")
    query_ids = Enum.map(SurfaceProviderRegistry.contributions(), & &1.query_id)
    assert "cadence.contract_probe.mission" in query_ids
    assert "cadence.contract_probe.snapshot" in query_ids
  end
end
