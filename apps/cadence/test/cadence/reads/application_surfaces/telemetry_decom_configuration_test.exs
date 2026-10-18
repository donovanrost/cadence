defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecomConfigurationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    Registry,
    Spacecraft,
    TelemetryDecom,
    TelemetryDecomFixtures
  }

  alias Cadence.Auth.Scope
  alias Cadence.MissionModels
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.Configuration

  @organization_id "org-decom-configuration"
  @mission_id "mission-decom-configuration"

  setup do
    {spacecraft, revision, endpoint} =
      TelemetryDecomFixtures.setup_imported_mission!(@organization_id, @mission_id)

    scope = TelemetryDecomFixtures.user_scope(@organization_id, "decom-configuration")
    host = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)
    {:ok, _} = ApplicationInstallations.install(scope, host, "telemetry_decom")
    {:ok, mission} = Missions.fetch_mission(@organization_id, @mission_id)

    %{
      scope: scope,
      host: host,
      spacecraft: spacecraft,
      revision: revision,
      endpoint: endpoint,
      mission: mission
    }
  end

  test "unconfigured producer mounts an explicit revision choice and persists its emitted action",
       c do
    assert {:ok, page} = Configuration.load(c.scope, c.host, c.mission)
    assert page["configuration"] == nil
    assert page["revision"]["field"]["value"] == ""
    assert page["preflight"]["check_count"] >= 3
    assert page["preflight"]["state"] == "blocked"
    assert page["preview"] == nil

    export_fixture("unconfigured", %{page: page, revision_id: c.revision.catalog_revision_id})
    input = client_action(page, c.revision.catalog_revision_id)

    assert input == %{
             "catalog_revision_id" => c.revision.catalog_revision_id,
             "handled_apids" => [],
             "expected_review" => page["review"]["configuration_token"]
           }

    assert {:ok, _} =
             ActionDispatcher.dispatch(c.scope, c.host, %ActionRequest{
               application_key: "telemetry_decom",
               application_version: 1,
               surface_id: "manage",
               surface_version: 1,
               action_id: "save_configuration",
               params: input
             })

    assert {:ok, saved} =
             TelemetryDecom.fetch_config(
               @organization_id,
               @mission_id,
               c.spacecraft.spacecraft_id
             )

    assert saved.catalog_revision_id == c.revision.catalog_revision_id
    assert {:ok, page} = Configuration.load(c.scope, c.host, c.mission)
    assert page["configuration"]["configuration_version"] == saved.configuration_version
    assert page["packet_handoff"]["row_count"] == 1
    assert page["packet_handoff"]["selection_count"] == 0

    assert Enum.find(page["preflight"]["checks"], &(&1["check_id"] == "packet-apid-binding"))[
             "state"
           ] == "blocked"
  end

  test "saved compiler evidence, lifecycle events and publication state reflect actual configuration",
       c do
    assert {:ok, config} =
             TelemetryDecom.configure(@organization_id, @mission_id, c.spacecraft.spacecraft_id,
               catalog_revision_id: c.revision.catalog_revision_id,
               handled_apids: [42],
               source_endpoint_id: c.endpoint.source_endpoint_id
             )

    assert {:ok, page} = Configuration.load(c.scope, c.host, c.mission)
    assert page["status"]["state"] == "configured"
    assert [entry] = page["review"]["configurations"]
    assert entry["spacecraft_name"] == c.spacecraft.display_name
    assert entry["source_endpoint_name"] == c.endpoint.display_name
    assert entry["source_endpoint_id"] == c.endpoint.source_endpoint_id
    assert page["status"]["tone"] == "attention"
    assert page["revision"]["field"]["value"] == config.catalog_revision_id
    assert page["packet_handoff"]["selection_count"] == 1
    assert page["packet_handoff"]["row_count"] == 1
    assert Enum.map(page["preview"]["stats"], & &1["value"]) == [1, 1, 0]
    assert page["lifecycle_actions"]["disable"]["event"] == "disable"
    assert page["lifecycle_actions"]["enable"]["event"] == "enable"
    assert page["lifecycle_actions"]["enable"]["action_id"] == "request_activation"
    refute page["preflight"]["activation_ready"]
    assert page["lifecycle_actions"]["enable"]["disabled"]

    assert {:ok, _} =
             MissionModels.approve_revision(
               @organization_id,
               @mission_id,
               c.revision.mission_model_revision_id,
               %{"kind" => "user", "id" => c.scope.user.user_id}
             )

    assert {:ok, page} = Configuration.load(c.scope, c.host, c.mission)
    assert page["preflight"]["activation_ready"]
    assert page["pending_activation"] == nil
    export_fixture("configured", %{page: page})

    assert {:ok, _} =
             TelemetryDecom.disable(@organization_id, @mission_id, c.spacecraft.spacecraft_id)

    assert {:ok, disabled} = Configuration.load(c.scope, c.host, c.mission)
    assert disabled["status"]["state"] == "disabled"
    assert disabled["lifecycle_actions"]["disable"] == nil
    assert disabled["lifecycle_actions"]["enable"]["disabled"] == false
    export_fixture("disabled", %{page: disabled})
  end

  test "pending mission requests show their durable identity and inhibit another request", c do
    revision = TelemetryDecomFixtures.persist_qualified_revision!(@organization_id, @mission_id)

    assert {:ok, _} =
             TelemetryDecom.configure(@organization_id, @mission_id, c.spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42],
               source_endpoint_id: c.endpoint.source_endpoint_id
             )

    assert {:ok, %{activation_request: request}} =
             TelemetryDecom.request_mission_apply(
               c.scope,
               @mission_id,
               c.spacecraft.spacecraft_id
             )

    assert request.state == :approval_pending
    assert {:ok, page} = Configuration.load(c.scope, c.host, c.mission)
    assert page["pending_activation"]["activation_request_id"] == request.activation_request_id
    assert page["lifecycle_actions"]["enable"]["disabled"]
    assert page["status"]["state"] == "configured"
    export_fixture("pending", %{page: page})

    assert {:ok, binding_set} =
             Cadence.Governance.fetch_binding_set(
               @organization_id,
               @mission_id,
               request.binding_set_id,
               request.binding_set_version
             )

    assert :ok =
             TelemetryDecom.activation_applied(binding_set, %{
               "composition" => "mission_applications"
             })

    assert {:ok, _} =
             Cadence.Activations.record_binding_set_activation(
               @organization_id,
               @mission_id,
               request.binding_set_id,
               request.binding_set_version,
               binding_set_content_sha256: request.binding_set_content_sha256
             )

    assert {:ok, applied} = Configuration.load(c.scope, c.host, c.mission)
    assert applied["status"]["state"] == "applied"
    assert applied["status"]["tone"] == "ready"
  end

  test "canonical and historical surface identities resolve to the same scoped domain read", c do
    {:ok, canonical} =
      Registry.fetch_surface(
        TelemetryDecom.definition(),
        :spacecraft,
        "manage"
      )

    {:ok, legacy} =
      Registry.fetch_surface(
        Spacecraft.definition(),
        :spacecraft,
        "telemetry_decom"
      )

    assert {:ok, current} =
             ApplicationSurfaces.load(
               c.scope,
               c.host,
               "telemetry_decom",
               1,
               canonical
             )

    assert {:ok, previous} =
             ApplicationSurfaces.load(c.scope, c.host, "spacecraft", 1, legacy)

    assert previous == current
    assert current["data"]["context"]["spacecraft_id"] == c.spacecraft.spacecraft_id

    unauthorized =
      Scope.new(%{
        user: %{c.scope.user | capabilities: []},
        organization_id: @organization_id
      })

    assert {:error, _reason} =
             ApplicationSurfaces.load(
               unauthorized,
               c.host,
               "telemetry_decom",
               1,
               canonical
             )
  end

  test "rejects cross-scope reads and unavailable installation", c do
    assert {:error, :invalid_application_scope} =
             Configuration.load(%{c.scope | organization_id: "other"}, c.host, c.mission)

    assert {:error, :invalid_application_scope} =
             Configuration.load(
               c.scope,
               HostContext.spacecraft("other", c.spacecraft.spacecraft_id),
               c.mission
             )

    other =
      TelemetryDecomFixtures.persist_spacecraft!(@organization_id, @mission_id,
        display_name: "Uninstalled"
      )

    assert {:error, :application_not_installed} =
             Configuration.load(
               c.scope,
               HostContext.spacecraft(@mission_id, other.spacecraft_id),
               c.mission
             )
  end

  defp export_fixture(name, value) do
    if directory = System.get_env("CADENCE_DECOM_FIXTURES") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, name <> ".json"), Jason.encode!(value))
    end
  end

  defp client_action(page, revision_id) do
    root = Path.expand("../../../../../../frontend", __DIR__)

    script =
      Path.join(root, "modules/telemetry-decom/src/features/configuration/producer-check.mjs")

    {output, status} =
      System.cmd("node", [script, Jason.encode!(%{page: page, revision_id: revision_id})],
        stderr_to_stdout: true
      )

    assert status == 0, output
    [_, encoded] = Regex.run(~r/CADENCE_DECOM_INPUT=([^\n]+)/, output)
    Jason.decode!(encoded)
  end
end
