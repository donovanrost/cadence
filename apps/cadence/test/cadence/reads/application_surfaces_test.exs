defmodule Cadence.Reads.ApplicationSurfacesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    Registry,
    SurfaceDefinition,
    SurfaceQueryContribution,
    SurfaceQueryRequest
  }

  alias Cadence.Auth.Scope

  alias Cadence.Reads.{ApplicationReferences, ApplicationSurfaces}
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry

  @organization_id "org-application-surfaces"
  @mission_id "mission-application-surfaces"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope, host_context: HostContext.mission(@mission_id)}
  end

  test "requires the exact active installation before loading a declared surface", context do
    decom = decom_surface("spacecraft-surface-install")

    assert {:error, :application_not_installed} =
             ApplicationSurfaces.load(
               context.scope,
               decom.host,
               decom.definition.application_key,
               decom.definition.version,
               decom.surface
             )

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               decom.host,
               decom.definition.application_key
             )

    assert {:ok, %{"data" => data}} =
             ApplicationSurfaces.load(
               context.scope,
               decom.host,
               decom.definition.application_key,
               decom.definition.version,
               decom.surface
             )

    assert is_map(data)
  end

  test "dispatches two contributed applications concurrently without cross-talk", context do
    contributions = [
      %SurfaceQueryContribution{
        application_key: "synthetic_alpha",
        application_version: 1,
        query_id: "synthetic.alpha.read",
        query_version: 1,
        provider: Cadence.TestSurfaceQueryProviders.Alpha
      },
      %SurfaceQueryContribution{
        application_key: "synthetic_beta",
        application_version: 1,
        query_id: "synthetic.beta.read",
        query_version: 1,
        provider: Cadence.TestSurfaceQueryProviders.Beta
      }
    ]

    providers = ProviderRegistry.providers(contributions)

    requests = [
      %SurfaceQueryRequest{
        application_key: "synthetic_alpha",
        application_version: 1,
        surface_id: "read",
        surface_version: 1,
        query_id: "synthetic.alpha.read",
        query_version: 1
      },
      %SurfaceQueryRequest{
        application_key: "synthetic_beta",
        application_version: 1,
        surface_id: "read",
        surface_version: 1,
        query_id: "synthetic.beta.read",
        query_version: 1
      }
    ]

    results =
      requests
      |> Task.async_stream(
        fn request ->
          ProviderRegistry.dispatch(context.scope, context.host_context, request, providers)
        end,
        max_concurrency: 2,
        ordered: true,
        timeout: 1_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert results == [
             {:ok, %{"provider" => "alpha", "application_key" => "synthetic_alpha"}},
             {:ok, %{"provider" => "beta", "application_key" => "synthetic_beta"}}
           ]
  end

  test "accepts the composed query registry at 128 contributions and fails closed at 129" do
    contributions =
      Enum.map(1..129, fn index ->
        %SurfaceQueryContribution{
          application_key: "synthetic_alpha",
          application_version: 1,
          query_id: "synthetic.alpha.#{index}",
          query_version: 1,
          provider: Cadence.TestSurfaceQueryProviders.Alpha
        }
      end)

    assert map_size(ProviderRegistry.providers(Enum.take(contributions, 128))) == 128
    assert ProviderRegistry.providers(contributions) == %{}
  end

  test "surface registry rejects duplicate query identities and invalid providers" do
    alpha = %SurfaceQueryContribution{
      application_key: "synthetic_alpha",
      application_version: 1,
      query_id: "synthetic.shared.read",
      query_version: 1,
      provider: Cadence.TestSurfaceQueryProviders.Alpha
    }

    beta_collision = %SurfaceQueryContribution{
      application_key: "synthetic_beta",
      application_version: 1,
      query_id: "synthetic.shared.read",
      query_version: 1,
      provider: Cadence.TestSurfaceQueryProviders.Beta
    }

    assert ProviderRegistry.providers([alpha, beta_collision]) == %{}
    assert ProviderRegistry.providers([alpha, alpha]) == %{}

    assert ProviderRegistry.providers([%{alpha | provider: String}]) == %{}

    mismatched_providers = %{
      {"synthetic_beta", "synthetic.shared.read"} => Cadence.TestSurfaceQueryProviders.Alpha
    }

    assert ProviderRegistry.dispatch(
             %Scope{},
             HostContext.mission("synthetic-mission"),
             %SurfaceQueryRequest{
               application_key: "synthetic_beta",
               application_version: 1,
               surface_id: "read",
               surface_version: 1,
               query_id: "synthetic.shared.read",
               query_version: 1
             },
             mismatched_providers
           ) == {:error, :invalid_application_surface_provider_registry}
  end

  test "spacecraft batch lookup performs one bounded repository query" do
    persist_test_spacecraft("batch-lookup-a")
    persist_test_spacecraft("batch-lookup-b")

    {result, query_count} =
      repo_query_count(fn ->
        Cadence.SpacecraftStore.fetch_spacecrafts(
          @organization_id,
          @mission_id,
          ["batch-lookup-a", "batch-lookup-b"]
        )
      end)

    assert {:ok, spacecrafts} = result
    assert Map.keys(spacecrafts) |> Enum.sort() == ["batch-lookup-a", "batch-lookup-b"]
    assert query_count == 1
  end

  test "spacecraft batch lookup rejects an oversized raw request before querying" do
    assert {:error, :batch_bounds_exceeded} =
             Cadence.SpacecraftStore.fetch_spacecrafts(
               @organization_id,
               @mission_id,
               Enum.map(1..101, &"oversized-#{&1}")
             )
  end

  test "rejects undeclared surface contracts even when their query id is known", context do
    decom = decom_surface("spacecraft-surface-undeclared")

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               decom.host,
               decom.definition.application_key
             )

    %SurfaceDefinition{} = surface = decom.surface

    altered_surface = %SurfaceDefinition{surface | surface_id: "operator-supplied-surface"}

    assert {:error, :undeclared_application_surface} =
             ApplicationSurfaces.load(
               context.scope,
               decom.host,
               decom.definition.application_key,
               decom.definition.version,
               altered_surface
             )
  end

  test "searches bounded reference pages through the authorized installed surface", context do
    decom = decom_surface("spacecraft-surface-references")
    {:ok, surface} = Registry.fetch_surface(decom.definition, :spacecraft, "manage")

    search = fn field, query ->
      ApplicationReferences.search(
        context.scope,
        decom.host,
        decom.definition.application_key,
        decom.definition.version,
        surface,
        field,
        query
      )
    end

    assert {:error, :application_not_installed} = search.("catalog_revision_id", "")

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               decom.host,
               decom.definition.application_key
             )

    # The revision choice is a select reference: it resolves with the surface, never by search.
    assert {:error, :reference_not_searchable} = search.("catalog_revision_id", "missing")

    assert {:error, :unknown_application_surface_reference} =
             search.("operator_field", "channel")

    assert {:ok, _installation} =
             ApplicationInstallations.disable(
               context.scope,
               decom.host,
               decom.definition.application_key
             )

    assert {:error, :application_installation_disabled} = search.("catalog_revision_id", "")
  end

  defp decom_surface(spacecraft_id) do
    persist_test_spacecraft(spacecraft_id)
    {:ok, definition} = Registry.fetch_available("telemetry_decom")
    {:ok, surface} = Registry.fetch_default_surface(definition, :spacecraft)

    %{
      host: HostContext.spacecraft(@mission_id, spacecraft_id),
      definition: definition,
      surface: surface
    }
  end

  defp persist_test_spacecraft(spacecraft_id) do
    spacecraft =
      Cadence.Spacecraft.new(%{
        mission_id: @mission_id,
        spacecraft_id: spacecraft_id,
        display_name: spacecraft_id
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)
  end

  defp repo_query_count(fun) do
    test_pid = self()
    reference = make_ref()
    handler_id = {__MODULE__, reference}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, _metadata, {pid, query_reference} ->
          send(pid, {:repo_query, query_reference})
        end,
        {test_pid, reference}
      )

    try do
      result = fun.()
      {result, drain_repo_queries(reference)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_repo_queries(reference, count \\ 0) do
    receive do
      {:repo_query, ^reference} -> drain_repo_queries(reference, count + 1)
    after
      0 -> count
    end
  end
end
