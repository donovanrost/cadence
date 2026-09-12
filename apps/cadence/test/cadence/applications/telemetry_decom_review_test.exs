defmodule Cadence.Applications.TelemetryDecomReviewTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    ConfigurationLock,
    HostContext,
    PacketBindings,
    TelemetryDecom,
    TelemetryDecomFixtures
  }

  alias Cadence.Applications.Spacecraft.ActionProvider, as: SpacecraftActions
  alias Cadence.Applications.TelemetryDecom.Review
  alias Cadence.Management.Activations
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.Configuration
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @organization_id "org-decom-review"
  @mission_id "mission-decom-review"

  setup do
    {spacecraft, revision, endpoint} =
      TelemetryDecomFixtures.setup_qualified_mission!(@organization_id, @mission_id)

    scope = TelemetryDecomFixtures.user_scope(@organization_id, "review")
    host = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)
    {:ok, installation} = ApplicationInstallations.install(scope, host, "telemetry_decom")

    %{
      scope: scope,
      host: host,
      spacecraft: spacecraft,
      revision: revision,
      endpoint: endpoint,
      installation: installation
    }
  end

  test "a reviewed first save cannot overwrite a configuration created since the review", c do
    first = evidence(c)

    assert {:error, %ActionFailure{code: "review_required"}} =
             dispatch(c, "save_configuration", attrs(c))

    assert {:error, :not_configured} =
             TelemetryDecom.fetch_config(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id
             )

    assert {:ok, saved} = dispatch(c, "save_configuration", reviewed(attrs(c), first))
    assert saved.configuration_version == 1

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             dispatch(
               c,
               "save_configuration",
               reviewed(Map.put(attrs(c), :handled_apids, []), first)
             )

    assert {:ok, current} =
             TelemetryDecom.fetch_config(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id
             )

    assert current.handled_apids == [42]
    assert current.configuration_version == 1
  end

  test "packet changes invalidate a review even if the catalog and application configuration version stay the same",
       c do
    assert {:ok, saved} =
             TelemetryDecom.configure(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id,
               attrs(c)
             )

    before = evidence(c)
    assert {:ok, telemetry} = TelemetryProjection.load(@organization_id, @mission_id, c.revision)
    [packet | _] = telemetry.packet_definitions

    assert {:ok, _} =
             PacketBindings.replace(
               c.scope,
               c.host,
               c.installation.application_installation_id,
               %{
                 input_id: "telemetry-fields",
                 input_version: 1,
                 catalog_revision_id: c.revision.catalog_revision_id,
                 source_endpoint_ref: c.endpoint.source_endpoint_id,
                 selected_packet_ids: [packet.packet_definition_id]
               }
             )

    assert {:ok, current} =
             TelemetryDecom.fetch_config(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id
             )

    assert current.configuration_version == saved.configuration_version
    assert current.catalog_revision_id == saved.catalog_revision_id

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             dispatch(c, "disable", reviewed(%{}, before))

    assert {:ok, installation} =
             ApplicationInstallations.fetch_installed(c.scope, c.host, "telemetry_decom")

    assert installation.lifecycle_state == :installed

    assert {:ok, [packets]} =
             PacketBindings.list(c.scope, c.host, installation.application_installation_id)

    assert packets.enabled
  end

  test "another spacecraft changes the mission review without invalidating a local configuration review",
       c do
    assert {:ok, _} =
             TelemetryDecom.configure(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id,
               attrs(c)
             )

    before = evidence(c)
    export_review("mission-before", c)

    other =
      TelemetryDecomFixtures.persist_spacecraft!(@organization_id, @mission_id,
        display_name: "Nova-2"
      )

    endpoint =
      TelemetryDecomFixtures.persist_source_endpoint!(
        @organization_id,
        @mission_id,
        other.spacecraft_id,
        display_name: "Secondary"
      )

    assert {:ok, _} =
             TelemetryDecom.configure(
               @organization_id,
               @mission_id,
               other.spacecraft_id,
               Map.put(attrs(c), :source_endpoint_id, endpoint.source_endpoint_id)
             )

    after_change = evidence(c)
    export_review("mission-after", c)
    assert after_change["configuration_token"] == before["configuration_token"]
    refute after_change["mission_token"] == before["mission_token"]
    assert length(after_change["configurations"]) == 2

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             dispatch(c, "request_activation", %{"expected_review" => before["mission_token"]})

    assert {:ok, nil} =
             Activations.latest_pending(
               c.scope,
               @mission_id,
               TelemetryDecom.binding_set_id(@mission_id)
             )

    assert {:ok, %{activation_request: request}} =
             dispatch(c, "request_activation", %{
               "expected_review" => after_change["mission_token"]
             })

    assert request.state == :approval_pending
    assert request.metadata["reviewed_configuration_basis"] == after_change["mission_token"]
  end

  test "the legacy spacecraft surface delegates reviewed actions and bounded results to the canonical authority",
       c do
    request = %ActionRequest{
      application_key: "spacecraft",
      application_version: 1,
      surface_id: "telemetry_decom",
      surface_version: 1,
      action_id: "save_configuration",
      params: reviewed(attrs(c), evidence(c))
    }

    assert {:ok, saved} = SpacecraftActions.execute(c.scope, c.host, request)
    assert SpacecraftActions.result(saved)["configurationVersion"] == 1

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             SpacecraftActions.execute(c.scope, c.host, request)

    disable = %{request | action_id: "disable", params: reviewed(%{}, evidence(c))}
    assert {:ok, disabled} = SpacecraftActions.execute(c.scope, c.host, disable)
    refute disabled.enabled

    assert {:error, :application_installation_disabled} =
             ApplicationInstallations.fetch_installed(c.scope, c.host, "telemetry_decom")
  end

  test "a failed reviewed operation rolls back nested configuration writes", c do
    before = evidence(c)

    assert {:error, :operation_failed} =
             Review.run(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id,
               "save_configuration",
               reviewed(%{}, before),
               fn ->
                 assert {:ok, _} =
                          TelemetryDecom.configure(
                            @organization_id,
                            @mission_id,
                            c.spacecraft.spacecraft_id,
                            attrs(c)
                          )

                 {:error, :operation_failed}
               end
             )

    assert {:error, :not_configured} =
             TelemetryDecom.fetch_config(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id
             )

    assert evidence(c) == before
  end

  test "independent transactions wait on the same mission even before any configuration exists" do
    parent = self()
    mission = "empty-lock-#{System.unique_integer([:positive])}"

    first =
      independent(fn ->
        ConfigurationLock.run(@organization_id, mission, fn ->
          send(parent, {:locked, self()})

          receive do
            :release -> :ok
          after
            5_000 -> raise "lock release was not delivered"
          end
        end)
      end)

    assert_receive {:locked, owner}, 2_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:waiting, pid})
        ConfigurationLock.run(@organization_id, mission, fn -> send(parent, :second_entered) end)
      end)

    assert_receive {:waiting, backend_pid}, 2_000
    assert wait_for_lock(backend_pid, 100)
    refute_received :second_entered

    other =
      independent(fn ->
        ConfigurationLock.run(@organization_id, mission <> "-other", fn ->
          :other_mission_entered
        end)
      end)

    assert Task.await(other) == :other_mission_entered
    send(owner, :release)
    assert Task.await(first) == :ok
    assert Task.await(second) == :second_entered
    assert_receive :second_entered
  end

  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_for_lock(_pid, 0), do: false

  defp wait_for_lock(pid, attempts) do
    %{rows: [[waiting]]} =
      SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND locktype = 'advisory' AND NOT granted)",
        [pid]
      )

    if waiting do
      true
    else
      Process.sleep(10)
      wait_for_lock(pid, attempts - 1)
    end
  end

  defp export_review(name, c) do
    if directory = System.get_env("CADENCE_DECOM_FIXTURES") do
      {:ok, mission} = Missions.fetch_mission(@organization_id, @mission_id)
      {:ok, page} = Configuration.load(c.scope, c.host, mission)
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, name <> ".json"), Jason.encode!(%{page: page}))
    end
  end

  defp evidence(c), do: Review.snapshot(@organization_id, @mission_id, c.spacecraft.spacecraft_id)

  defp reviewed(attrs, evidence),
    do: Map.put(attrs, "expected_review", evidence["configuration_token"])

  defp attrs(c),
    do: %{
      catalog_revision_id: c.revision.catalog_revision_id,
      source_endpoint_id: c.endpoint.source_endpoint_id,
      handled_apids: [42]
    }

  defp dispatch(c, action, params) do
    ActionDispatcher.dispatch(c.scope, c.host, %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: action,
      params: params
    })
  end
end
