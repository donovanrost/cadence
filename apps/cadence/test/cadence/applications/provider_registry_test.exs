defmodule Cadence.Applications.ProviderRegistryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.{
    ActionProviderRegistry,
    ActionRequest,
    ApplicationDefinition,
    HostContext,
    HostQueryRegistry,
    JSONBoundary,
    Registry,
    SurfaceDefinition,
    SurfaceQueryContribution
  }

  alias Cadence.Applications.Spacecraft
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry, as: SurfaceProviderRegistry

  @scope %Scope{actor_kind: :user, organization_id: "org-registry"}
  @host_context HostContext.mission("mission-registry")

  test "dispatches distinct host-query providers concurrently by exact identity" do
    providers =
      HostQueryRegistry.providers([
        Cadence.TestHostQueryContributors.Alpha,
        Cadence.TestHostQueryContributors.Beta
      ])

    requests = [
      %{"applicationKey" => "synthetic_alpha", "queryId" => "synthetic.shared.read"},
      %{"applicationKey" => "synthetic_beta", "queryId" => "synthetic.beta.read"}
    ]

    results =
      Task.async_stream(
        requests,
        fn request -> HostQueryRegistry.dispatch(@scope, @host_context, request, providers) end,
        max_concurrency: 2,
        ordered: true,
        timeout: 1_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert results == [
             {:ok, %{"provider" => "alpha", "applicationKey" => "synthetic_alpha"}},
             {:ok, %{"provider" => "beta", "applicationKey" => "synthetic_beta"}}
           ]
  end

  test "host-query identity mismatch never falls through to another provider" do
    providers =
      HostQueryRegistry.providers([
        Cadence.TestHostQueryContributors.Alpha,
        Cadence.TestHostQueryContributors.Beta
      ])

    assert {:error, :application_query_identity_mismatch} =
             HostQueryRegistry.dispatch(
               @scope,
               @host_context,
               %{"applicationKey" => "synthetic_beta", "queryId" => "synthetic.shared.read"},
               providers
             )

    assert {:error, :application_query_identity_mismatch} =
             HostQueryRegistry.dispatch(
               @scope,
               @host_context,
               %{"queryId" => "synthetic.shared.read"},
               providers
             )
  end

  test "canonical surface queries fall through compatibility host-query dispatch" do
    assert :not_handled =
             HostQueryRegistry.dispatch(
               @scope,
               @host_context,
               %{
                 "applicationKey" => "comms",
                 "queryId" => "cadence.comms.overview"
               }
             )
  end

  test "host-query dispatch rejects a provider whose identity differs from its map key" do
    providers = %{
      {"synthetic_alpha", "synthetic.shared.read"} => Cadence.TestHostQueryProviders.Beta
    }

    assert {:error, :invalid_application_host_query_provider_registry} =
             HostQueryRegistry.dispatch(
               @scope,
               @host_context,
               %{"applicationKey" => "synthetic_alpha", "queryId" => "synthetic.shared.read"},
               providers
             )
  end

  test "host-query registry rejects duplicate identities, collisions, bad contributors, and overflow" do
    assert HostQueryRegistry.providers([
             Cadence.TestHostQueryContributors.Alpha,
             Cadence.TestHostQueryContributors.Collision
           ]) == %{}

    assert HostQueryRegistry.providers([
             Cadence.TestHostQueryContributors.Alpha,
             Cadence.TestHostQueryContributors.DuplicateApplication
           ]) == %{}

    assert HostQueryRegistry.providers([Cadence.TestHostQueryContributors.Raising]) == %{}
    assert HostQueryRegistry.providers([Cadence.TestHostQueryProviders.Invalid]) == %{}

    assert HostQueryRegistry.providers(
             Enum.map(1..17, fn _index -> Cadence.TestHostQueryContributors.Alpha end)
           ) == %{}
  end

  test "host-query output rejects invalid and oversized values before transport" do
    invalid_providers =
      HostQueryRegistry.providers([Cadence.TestHostQueryContributors.InvalidOutput])

    assert {:error, :invalid_application_host_query_output} =
             HostQueryRegistry.dispatch(
               @scope,
               @host_context,
               %{
                 "applicationKey" => "synthetic_invalid_output",
                 "queryId" => "synthetic.invalid.output"
               },
               invalid_providers
             )

    oversized_providers =
      HostQueryRegistry.providers([Cadence.TestHostQueryContributors.OversizedOutput])

    assert {:error, :application_host_query_output_bounds_exceeded} =
             HostQueryRegistry.dispatch(
               @scope,
               @host_context,
               %{
                 "applicationKey" => "synthetic_oversized_output",
                 "queryId" => "synthetic.oversized.output"
               },
               oversized_providers
             )
  end

  test "surface registry permits multiple distinct queries for one application" do
    contributions = [
      %SurfaceQueryContribution{
        application_key: "synthetic_alpha",
        application_version: 1,
        query_id: "synthetic.alpha.one",
        query_version: 1,
        provider: Cadence.TestSurfaceQueryProviders.Alpha
      },
      %SurfaceQueryContribution{
        application_key: "synthetic_alpha",
        application_version: 1,
        query_id: "synthetic.alpha.two",
        query_version: 1,
        provider: Cadence.TestSurfaceQueryProviders.Alpha
      }
    ]

    assert SurfaceProviderRegistry.providers(contributions) == %{
             {"synthetic_alpha", "synthetic.alpha.one"} =>
               Cadence.TestSurfaceQueryProviders.Alpha,
             {"synthetic_alpha", "synthetic.alpha.two"} => Cadence.TestSurfaceQueryProviders.Alpha
           }

    query_collision = %SurfaceQueryContribution{
      application_key: "synthetic_beta",
      application_version: 1,
      query_id: "synthetic.alpha.one",
      query_version: 1,
      provider: Cadence.TestSurfaceQueryProviders.Beta
    }

    assert SurfaceProviderRegistry.providers(contributions ++ [query_collision]) == %{}
  end

  test "surface registry requires authoritative contributions and permits optional surfaces" do
    definitions = Registry.all()
    providers = SurfaceProviderRegistry.providers()

    expected_contribution_counts = %{
      "comms" => 15,
      "spacecraft" => 12,
      "mission_catalog" => 10,
      "telemetry_decom" => 1,
      "derived_telemetry" => 1,
      "limits" => 2,
      "ops_console" => 35,
      "organization_admin" => 12
    }

    assert length(SurfaceProviderRegistry.contributions()) == 88
    assert map_size(providers) == 88

    assert providers
           |> Map.keys()
           |> Enum.frequencies_by(&elem(&1, 0)) == expected_contribution_counts

    assert :ok = SurfaceProviderRegistry.validate(definitions, providers)

    assert Map.has_key?(providers, {"comms", "cadence.comms.overview"})

    assert Map.fetch!(providers, {"comms", "cadence.comms.provider_list"}) ==
             Cadence.Reads.ApplicationSurfaces.CommsProviders

    assert Map.fetch!(providers, {"comms", "cadence.comms.provider_new"}) ==
             Cadence.Reads.ApplicationSurfaces.CommsProviders

    assert Map.fetch!(providers, {"comms", "cadence.comms.provider_show"}) ==
             Cadence.Reads.ApplicationSurfaces.CommsProviders

    declared_keys =
      for definition <- definitions,
          surface <- definition.surfaces,
          query_id = Map.get(surface.data_contract, :query_id),
          is_binary(query_id),
          do: {definition.application_key, query_id}

    authoritative_keys =
      for contribution <- SurfaceProviderRegistry.contributions(),
          do: {contribution.application_key, contribution.query_id}

    assert MapSet.subset?(MapSet.new(authoritative_keys), MapSet.new(declared_keys))

    assert {:error, :invalid_application_surface_provider_registry} =
             SurfaceProviderRegistry.validate(
               definitions,
               Map.delete(providers, {"comms", "cadence.comms.overview"})
             )

    assert {:error, :invalid_application_surface_provider_registry} =
             SurfaceProviderRegistry.validate(
               definitions,
               Map.put(
                 providers,
                 {"comms", "cadence.comms.unknown"},
                 Cadence.Reads.ApplicationSurfaces.Comms
               )
             )

    optional_surface = %SurfaceDefinition{
      surface_id: "optional",
      version: 1,
      purpose: :overview,
      scope: :mission,
      placement: :application_workspace,
      data_contract: %{query_id: "cadence.comms.optional", version: 1},
      renderer: {:trusted, "cadence.comms.optional"}
    }

    definitions_with_optional_surface =
      Enum.map(definitions, fn
        %ApplicationDefinition{application_key: "comms"} = definition ->
          %{definition | surfaces: definition.surfaces ++ [optional_surface]}

        definition ->
          definition
      end)

    assert :ok =
             SurfaceProviderRegistry.validate(definitions_with_optional_surface, providers)
  end

  test "dispatches distinct action providers concurrently and rejects registry drift" do
    providers =
      ActionProviderRegistry.providers([
        Cadence.TestActionContributors.Alpha,
        Cadence.TestActionContributors.Beta
      ])

    requests = [
      %ActionRequest{
        application_key: "synthetic_alpha",
        application_version: 1,
        action_id: "run"
      },
      %ActionRequest{application_key: "synthetic_beta", application_version: 1, action_id: "run"}
    ]

    results =
      Task.async_stream(
        requests,
        fn request ->
          with {:ok, provider} <- ActionProviderRegistry.fetch(request.application_key, providers),
               {:ok, result} <- provider.execute(@scope, @host_context, request) do
            result
          end
        end,
        max_concurrency: 2,
        ordered: true,
        timeout: 1_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert results == [
             %{"provider" => "alpha", "missionId" => "mission-registry"},
             %{"provider" => "beta", "missionId" => "mission-registry"}
           ]

    assert ActionProviderRegistry.providers([
             Cadence.TestActionContributors.Alpha,
             Cadence.TestActionContributors.Collision
           ]) == %{}

    assert {:error, :unknown_application_action_provider} =
             ActionProviderRegistry.fetch(
               "synthetic_alpha",
               %{
                 "synthetic_alpha" => Cadence.TestActionProviders.Alpha,
                 "synthetic_invalid" => nil
               }
             )

    assert {:error, :unknown_application_action_provider} =
             ActionProviderRegistry.fetch(
               "synthetic_alpha",
               %{"synthetic_alpha" => Cadence.TestActionProviders.Beta}
             )

    assert ActionProviderRegistry.providers([Cadence.TestActionContributors.Raising]) == %{}
    assert ActionProviderRegistry.providers([Cadence.TestActionContributors.Invalid]) == %{}

    invalid_output_providers =
      ActionProviderRegistry.providers([Cadence.TestActionContributors.InvalidOutput])

    {:ok, invalid_output_provider} =
      ActionProviderRegistry.fetch("synthetic_invalid_output", invalid_output_providers)

    assert {:ok, invalid_output} =
             invalid_output_provider.execute(
               @scope,
               @host_context,
               %ActionRequest{
                 application_key: "synthetic_invalid_output",
                 application_version: 1,
                 action_id: "run"
               }
             )

    assert {:error, :unsupported} = JSONBoundary.validate(invalid_output)

    assert ActionProviderRegistry.providers(
             Enum.map(1..17, fn _index -> Cadence.TestActionContributors.Alpha end)
           ) == %{}
  end

  test "registers Spacecraft through its stable application identity" do
    assert Spacecraft.application_key() == "spacecraft"

    assert ActionProviderRegistry.providers([Spacecraft]) == %{
             "spacecraft" => Cadence.Applications.Spacecraft.ActionProvider
           }
  end
end
