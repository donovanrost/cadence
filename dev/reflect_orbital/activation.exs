defmodule Cadence.Dev.ReflectOrbital.Activation do
  @moduledoc "Activates and verifies the complete Earendil configuration through the governed APIs."
  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts, Review}
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Control.SpacecraftModelBindings
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Runtime.{MissionModelPlanDecoder, MissionRuntimeSpec, PartitionKey}

  def run(single_operator?) do
    if Application.get_env(:cadence_web, CadenceWeb.Endpoint, [])[:code_reloader] != true,
      do: raise("Earendil activation is restricted to the development server")

    scope = scope()
    {:ok, mission} = Cadence.Missions.fetch_mission(F.organization_id(), F.mission_id())

    {:ok, revision} =
      Cadence.Catalog.latest_revision(
        F.organization_id(),
        F.mission_id(),
        "catalog-earendil-command-telemetry"
      )

    fleet = Cadence.SpacecraftStore.list_spacecraft(F.organization_id(), F.mission_id())
    500 = length(fleet)
    snapshots = Map.new(fleet, &{&1.spacecraft_id, Drafts.snapshot(mission, &1)})

    Enum.each(snapshots, fn {_id, snapshot} ->
      true = snapshot.row != nil and not snapshot.external_changes
      true = snapshot.document["catalog_revision_id"] == revision.catalog_revision_id
      true = snapshot.document["telemetry_enabled"] and snapshot.document["commanding_enabled"]
      [0, 1, 10, 20, 30, 40, 50, 100, 101, 255] = snapshot.document["handled_apids"]
    end)

    policy = ActivationPolicy.load(F.organization_id(), F.mission_id())

    if policy.effective["approval_requirement"] != "direct" do
      unless single_operator?,
        do: raise("Independent approval is required; use the normal approval workflow")

      {:ok, _} =
        ActivationPolicy.save(scope, F.mission_id(), policy.token, %{
          "value" => %{"approval_requirement" => "direct"}
        })
    end

    {:ok, active} = Active.load(mission)

    already_active? =
      Enum.all?(snapshots, fn {id, snapshot} ->
        get_in(active.entries, [id, "configuration_revision_id"]) ==
          snapshot.row.configuration_revision_id
      end)

    unless already_active? do
      policy = ActivationPolicy.load(F.organization_id(), F.mission_id())
      tokens = Map.new(snapshots, fn {id, snapshot} -> {id, snapshot.token} end)
      IO.puts("Preparing one exact activation review for 500 spacecraft")

      {:ok, request} =
        Review.request_many(scope, F.mission_id(), tokens,
          expected_policy_token: policy.token,
          expected_approval_required: false
        )

      IO.puts("Executing approved fleet request #{request.activation_request_id}")

      {:ok, approved} =
        Cadence.Management.Activations.fetch_approved(request.activation_request_id)

      {:ok, execution} = Cadence.Control.Activations.execute(approved)
      :succeeded = execution.status
    end

    verify(mission, fleet, revision)
  end

  defp verify(mission, fleet, revision) do
    {:ok, active} = Active.load(mission)
    500 = map_size(active.entries)
    {:ok, spec} = Cadence.Runtime.Missions.applied_spec(F.mission_id())
    true = spec.generation == active.activation.generation
    5_000 = length(spec.binding_set.capability_instances)
    verify_routes(fleet, active.entries)

    {:ok, verified} =
      Cadence.Activations.with_locked_command_basis(
        F.organization_id(),
        F.mission_id(),
        fn activation ->
          Enum.each(fleet, fn craft ->
            entry = active.entries[craft.spacecraft_id]
            source = entry["document"]["telemetry_source_endpoint_id"]

            {:ok, config} =
              TelemetryDecom.fetch_config(
                F.organization_id(),
                F.mission_id(),
                craft.spacecraft_id
              )

            true = config.enabled and config.applied_at != nil
            true = config.applied_binding_set_version == active.binding_set.version
            true = config.catalog_revision_id == revision.catalog_revision_id

            {:ok, partition} =
              MissionRuntimeSpec.for_partition(spec, %PartitionKey{
                affinity: :source_endpoint,
                value: source
              })

            true = partition.mission_model_revision_id == revision.mission_model_revision_id
            {:ok, basis} = SpacecraftModelBindings.command_basis(activation, source)
            true = basis.mission_model_revision_id == revision.mission_model_revision_id

            {:ok, catalog} =
              MissionModelPlanDecoder.command_authoring_catalog(basis.runtime_plans)

            27 = length(catalog.runtime_definitions)
          end)

          {:ok, length(fleet)}
        end
      )

    %{
      spacecraft: verified,
      generation: spec.generation,
      telemetry_packet_bindings: length(spec.binding_set.capability_instances),
      commands_per_spacecraft: 27,
      catalog_revision_id: revision.catalog_revision_id,
      source_runtime_bases: map_size(spec.source_runtime_bases)
    }
  end

  defp verify_routes(fleet, entries) do
    fleet
    |> Enum.with_index(1)
    |> Enum.each(fn {craft, index} ->
      source = entries[craft.spacecraft_id]["document"]["telemetry_source_endpoint_id"]

      {:ok, %{routes: routes, findings: []}} =
        Cadence.Contacts.ProviderScheduling.list_ready_downlink_routes(
          F.organization_id(),
          F.mission_id(),
          craft.spacecraft_id
        )

      2 = length(routes)
      true = Enum.all?(routes, &(&1.source_endpoint_id == source))

      if rem(index, 100) == 0,
        do: IO.puts("Verified decoder and both provider routes for #{index}/500 spacecraft")
    end)
  end

  defp scope do
    {:ok, user} =
      Cadence.Accounts.fetch_user_by_email(
        System.get_env("EARENDIL_DEMO_EMAIL", "admin@example.com")
      )

    {:ok, organization} = Cadence.Organizations.fetch_organization(F.organization_id())
    {:ok, membership} = Cadence.Accounts.fetch_user_membership(user.user_id, F.organization_id())

    Cadence.Auth.Scope.new(%{
      user: user,
      organization: organization,
      organization_membership: membership
    })
  end
end
