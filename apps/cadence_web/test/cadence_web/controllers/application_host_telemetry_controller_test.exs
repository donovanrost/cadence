defmodule CadenceWeb.ApplicationHostTelemetryControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    PacketBindings,
    TelemetryDecom
  }

  alias Cadence.Applications.TelemetryDecom.Review
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.{ApplicationActionIdempotency, TestFixtures}

  @bridge_prefix "/api/cadence/application-host/v1/missions"

  test "catalog advertises the telemetry packet bindings manifest for a spacecraft", %{
    conn: _conn
  } do
    context = telemetry_context()
    member_conn = %{context.member_conn | host: "localhost", port: 4001}
    {_catalog_conn, catalog} = fetch_catalog(member_conn, context)

    assert application =
             Enum.find(catalog["applications"], &(&1["applicationKey"] == "telemetry_decom"))

    assert application["applicationKey"] == "telemetry_decom"
    assert application["applicationVersion"] == 1
    assert application["surface"]["surfaceId"] == "packet_bindings"
    assert application["surface"]["version"] == 1

    assert application["surface"]["dataContract"] == %{
             "id" => "cadence.packet_bindings.manage",
             "version" => 1
           }

    assert application["surface"]["actions"] == ["save_packet_bindings"]

    assert application["release"] == %{
             "federation" => "module_federation",
             "releaseId" => "telemetry-decom-v1",
             "remoteName" => "cadence_telemetry_decom",
             "manifestUrl" =>
               "http://localhost:4001/assets/application-host/telemetry-decom/mf-manifest.json",
             "exposedModule" => "./Application"
           }
  end

  test "authorized spacecraft query returns the scoped packet feature contract", %{conn: _conn} do
    context = telemetry_context()
    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(query_path(context), query_body(context))

    body = json_response(response, 200)

    assert Map.keys(body) |> Enum.sort() == ["host", "navigation", "trusted_surface"]

    assert body["host"] == %{
             "application_installation_id" => context.installation.application_installation_id,
             "application_key" => "telemetry_decom",
             "application_version" => 1,
             "dom_id" => "spacecraft-application-host",
             "renderer" => "trusted",
             "surface_id" => "packet_bindings"
           }

    assert body["trusted_surface"]["contract_version"] == 1
    assert body["trusted_surface"]["context"]["spacecraft_id"] == context.spacecraft.spacecraft_id
    assert body["trusted_surface"]["configuration"] == nil
    assert body["trusted_surface"]["packets"]["items"] == []
    assert body["navigation"]["fallback_href"] == body["trusted_surface"]["links"]["manage"]
    assert body == Jason.decode!(Jason.encode!(body))
  end

  test "configuration query mounts the module form and its submission persists through the bridge" do
    context = telemetry_context()
    {revision, _endpoint} = imported_packet_context(context)
    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    body =
      Map.merge(query_body(context), %{
        "surfaceId" => "manage",
        "queryId" => "cadence.telemetry_decom.manage"
      })

    response = catalog_conn |> bridge_conn(catalog) |> post_json(query_path(context), body)
    page = json_response(response, 200)["trusted_surface"]
    assert page["contract_version"] == 1
    assert page["configuration"] == nil
    assert page["context"]["spacecraft_id"] == context.spacecraft.spacecraft_id

    root = Path.expand("../../../../../frontend", __DIR__)

    script =
      Path.join(root, "modules/telemetry-decom/src/features/configuration/producer-check.mjs")

    {output, status} =
      System.cmd(
        "node",
        [script, Jason.encode!(%{page: page, revision_id: revision.catalog_revision_id})],
        stderr_to_stdout: true
      )

    assert status == 0, output
    [_, input] = Regex.run(~r/CADENCE_DECOM_INPUT=([^\n]+)/, output)

    action = %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "actionId" => "save_configuration",
      "scope" => scope_document(context),
      "input" => Jason.decode!(input)
    }

    saved =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "decom-configuration-save")
      |> post_json(action_path(context), action)

    assert json_response(saved, 200)["result"]["configurationVersion"] == 1
    refreshed = catalog_conn |> bridge_conn(catalog) |> post_json(query_path(context), body)
    current = json_response(refreshed, 200)["trusted_surface"]
    assert current["configuration"]["catalog_revision_id"] == revision.catalog_revision_id
    assert current["packet_handoff"]["row_count"] > 0

    stale =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "decom-stale-review")
      |> post_json(action_path(context), action)

    assert json_response(stale, 422)["code"] == "review_conflict"
    assert json_response(stale, 422)["message"] =~ "Refresh this page"

    repeated =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "decom-stale-review")
      |> post_json(action_path(context), action)

    assert repeated.resp_body == stale.resp_body

    invalid_version =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "decom-invalid-version")
      |> post_json(action_path(context), Map.put(action, "actionVersion", 2))

    assert json_response(invalid_version, 404)["code"] == "unsupported_action"

    current_page =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(query_path(context), body)
      |> json_response(200)
      |> Map.fetch!("trusted_surface")

    disabled =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "decom-disable")
      |> post_json(action_path(context), %{
        action
        | "actionId" => "disable",
          "input" => %{"expected_review" => current_page["review"]["configuration_token"]}
      })

    assert json_response(disabled, 200)["result"]["enabled"] == false
    unavailable = catalog_conn |> bridge_conn(catalog) |> post_json(query_path(context), body)
    assert json_response(unavailable, 404)["code"] == "application_unavailable"
  end

  test "successful save resolves the declared action version and persists packet-id selection", %{
    conn: _conn
  } do
    context = telemetry_context()
    {revision, endpoint} = imported_packet_context(context)

    assert {:ok, _config} =
             TelemetryDecom.configure(
               context.organization.organization_id,
               context.mission.mission_id,
               context.spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42],
               source_endpoint_id: endpoint.source_endpoint_id
             )

    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    query_response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(query_path(context), query_body(context))

    page = json_response(query_response, 200)["trusted_surface"]
    assert [%{"id" => packet_id}] = page["packets"]["items"]

    script =
      Path.expand(
        "../../../../../frontend/modules/telemetry-decom/src/features/packet-bindings/producer-check.mjs",
        __DIR__
      )

    {output, status} = System.cmd("node", [script, Jason.encode!(page)], stderr_to_stdout: true)
    assert status == 0, output
    [_, input] = Regex.run(~r/CADENCE_PACKET_INPUT=([^\n]+)/, output)

    action =
      action_body(context, revision, endpoint, packet_id)
      |> Map.put("input", Jason.decode!(input))

    action_response =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "telemetry-save-1")
      |> post_json(action_path(context), action)

    first_response_body = action_response.resp_body
    receipt = json_response(action_response, 200)

    assert {:ok, idempotency_key_digest} =
             ApplicationActionIdempotency.key_digest("telemetry-save-1")

    assert Map.keys(receipt) |> Enum.sort() == ["completedAt", "receiptId", "result"]
    assert receipt["receiptId"] == "application-host-receipt-" <> idempotency_key_digest
    assert {:ok, _completed_at, 0} = DateTime.from_iso8601(receipt["completedAt"])

    assert %{
             "applicationKey" => "telemetry_decom",
             "applicationVersion" => 1,
             "bindingCount" => 1,
             "configurationId" => configuration_id,
             "configurationVersion" => 1,
             "enabled" => true,
             "inputId" => "telemetry-fields",
             "inputVersion" => 1,
             "selectedPacketIds" => [^packet_id]
           } = receipt["result"]

    assert is_binary(configuration_id) and configuration_id != ""

    replay_response =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "telemetry-save-1")
      |> post_json(action_path(context), action)

    assert replay_response.status == 200
    assert replay_response.resp_body == first_response_body

    stale =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "telemetry-stale-review")
      |> post_json(action_path(context), action)

    assert json_response(stale, 422)["code"] == "review_conflict"

    assert {:ok, [configuration]} =
             PacketBindings.list(
               context.scope,
               context.host_context,
               context.installation.application_installation_id
             )

    assert configuration.configuration_version == 1
    assert [%{packet_id: ^packet_id}] = configuration.bindings
  end

  test "unapproved mission model blocks activation with actionable preflight evidence" do
    context = telemetry_context()
    {revision, endpoint} = imported_packet_context(context)

    {:ok, _} =
      TelemetryDecom.configure(
        context.organization.organization_id,
        context.mission.mission_id,
        context.spacecraft.spacecraft_id,
        catalog_revision_id: revision.catalog_revision_id,
        handled_apids: [42],
        source_endpoint_id: endpoint.source_endpoint_id
      )

    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    query =
      Map.merge(query_body(context), %{
        "surfaceId" => "manage",
        "queryId" => "cadence.telemetry_decom.manage"
      })

    response = catalog_conn |> bridge_conn(catalog) |> post_json(query_path(context), query)
    page = json_response(response, 200)["trusted_surface"]
    assert page["preflight"]["state"] == "blocked"

    assert %{"state" => "blocked", "title" => "Mission model approval required"} =
             Enum.find(page["preflight"]["checks"], &(&1["check_id"] == "mission-model-approval"))

    assert page["lifecycle_actions"]["enable"]["disabled"]

    action = %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "actionId" => "request_activation",
      "scope" => scope_document(context),
      "input" => %{"expected_review" => page["review"]["mission_token"]}
    }

    denied =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "unapproved-mission-model")
      |> post_json(action_path(context), action)

    assert json_response(denied, 422)["code"] == "preflight_blocked"

    assert {:ok, nil} =
             Activations.latest_pending(
               context.scope,
               context.mission.mission_id,
               TelemetryDecom.binding_set_id(context.mission.mission_id)
             )
  end

  test "mismatched explicit action versions fail closed", %{conn: _conn} do
    context = telemetry_context()
    {revision, endpoint} = imported_packet_context(context)
    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    for version_key <- ["actionVersion", "version"] do
      response =
        catalog_conn
        |> bridge_conn(catalog)
        |> put_req_header("idempotency-key", "telemetry-version-#{version_key}")
        |> post_json(
          action_path(context),
          Map.put(action_body(context, revision, endpoint, "packet"), version_key, 2)
        )

      assert %{"code" => "unsupported_action"} = json_response(response, 404)
    end
  end

  test "stale packet-binding versions map to a stable conflict", %{conn: _conn} do
    context = telemetry_context()
    {revision, endpoint} = imported_packet_context(context)

    assert {:ok, _} =
             TelemetryDecom.configure(
               context.organization.organization_id,
               context.mission.mission_id,
               context.spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42],
               source_endpoint_id: endpoint.source_endpoint_id
             )

    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    body = action_body(context, revision, endpoint, "missing-packet", expected_version: 99)

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "telemetry-stale-1")
      |> post_json(action_path(context), body)

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "packet_binding_version_conflict"
           } = json_response(response, 409)
  end

  test "undeclared query and action contracts fail closed", %{conn: _conn} do
    context = telemetry_context()
    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    query_response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(
        query_path(context),
        Map.put(query_body(context), "queryId", "cadence.packet_bindings.unknown")
      )

    assert %{"code" => "unsupported_query"} = json_response(query_response, 404)

    action_response =
      catalog_conn
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "telemetry-unknown-action-1")
      |> post_json(
        action_path(context),
        action_body(
          context,
          %{catalog_revision_id: "revision-missing"},
          %{source_endpoint_id: "endpoint"},
          "packet"
        )
        |> Map.put("actionId", "unknown_action")
      )

    assert %{"code" => "unsupported_action"} = json_response(action_response, 404)
  end

  test "a catalog session cannot be reused for another spacecraft scope", %{conn: _conn} do
    context = telemetry_context()
    other_spacecraft = TestFixtures.persist_spacecraft!(context.mission, display_name: "Other")
    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(
        query_path(context, other_spacecraft.spacecraft_id),
        query_body(context, other_spacecraft.spacecraft_id)
      )

    assert %{"code" => "invalid_scope"} = json_response(response, 400)
  end

  test "disabled and uninstalled applications are not admitted", %{conn: _conn} do
    disabled = telemetry_context()
    {catalog_conn, catalog} = fetch_catalog(disabled.member_conn, disabled)

    assert {:ok, _installation} =
             ApplicationInstallations.disable(
               disabled.scope,
               disabled.host_context,
               "telemetry_decom"
             )

    disabled_response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(query_path(disabled), query_body(disabled))

    assert %{"code" => "application_unavailable"} = json_response(disabled_response, 404)

    uninstalled = telemetry_context()
    {uninstalled_conn, uninstalled_catalog} = fetch_catalog(uninstalled.member_conn, uninstalled)

    assert {:ok, _installation} =
             ApplicationInstallations.uninstall(
               uninstalled.scope,
               uninstalled.host_context,
               "telemetry_decom"
             )

    uninstalled_response =
      uninstalled_conn
      |> bridge_conn(uninstalled_catalog)
      |> post_json(query_path(uninstalled), query_body(uninstalled))

    assert %{"code" => "application_unavailable"} = json_response(uninstalled_response, 404)
  end

  test "actions require a non-empty idempotency key", %{conn: _conn} do
    context = telemetry_context()
    {revision, endpoint} = imported_packet_context(context)
    {catalog_conn, catalog} = fetch_catalog(context.member_conn, context)

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json(action_path(context), action_body(context, revision, endpoint, "packet"))

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "idempotency_key_required"
           } = json_response(response, 400)
  end

  defp telemetry_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    assert {:ok, installation} =
             ApplicationInstallations.install(scope, host_context, "telemetry_decom")

    %{
      member_conn: TestFixtures.member_conn(user),
      organization: organization,
      mission: mission,
      spacecraft: spacecraft,
      scope: scope,
      host_context: host_context,
      installation: installation
    }
  end

  defp imported_packet_context(context) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    database = TestFixtures.persist_catalog_database!(context.mission, slug: "bridge-#{suffix}")

    run =
      TestFixtures.start_catalog_revision_import!(database,
        revision_label: "Bridge Revision",
        source_artifact: """
        packets:
          - name: HEALTH
            apid: 42
            items:
              - name: mode
                data_type: uint
                bit_offset: 0
                bit_size: 8
        commands: []
        """
      )

    TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(run)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "bridge-source-#{suffix}",
        mission_id: context.mission.mission_id,
        spacecraft_id: context.spacecraft.spacecraft_id,
        display_name: "Bridge Downlink"
      })

    assert {:ok, endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(
               context.organization.organization_id,
               endpoint
             )

    {revision, endpoint}
  end

  defp fetch_catalog(conn, context) do
    response = get(conn, catalog_path(context))
    {response, json_response(response, 200)}
  end

  defp catalog_path(context),
    do:
      @bridge_prefix <>
        "/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}/catalog"

  defp query_path(context, spacecraft_id \\ nil) do
    spacecraft_id = spacecraft_id || context.spacecraft.spacecraft_id
    @bridge_prefix <> "/#{context.mission.mission_id}/spacecraft/#{spacecraft_id}/query"
  end

  defp action_path(context),
    do:
      @bridge_prefix <>
        "/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}/actions"

  defp query_body(context, spacecraft_id \\ nil) do
    spacecraft_id = spacecraft_id || context.spacecraft.spacecraft_id

    %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "packet_bindings",
      "surfaceVersion" => 1,
      "queryId" => "cadence.packet_bindings.manage",
      "queryVersion" => 1,
      "scope" => scope_document(context, spacecraft_id),
      "params" => %{}
    }
  end

  defp action_body(context, revision, endpoint, packet_id, opts \\ []) do
    review =
      Review.snapshot(
        context.organization.organization_id,
        context.mission.mission_id,
        context.spacecraft.spacecraft_id
      )

    params = %{
      "expected_review" => review["configuration_token"],
      "input_id" => "telemetry-fields",
      "input_version" => 1,
      "catalog_revision_id" => revision_value(revision),
      "source_endpoint_ref" => endpoint_value(endpoint),
      "selected_packet_ids" => [packet_id]
    }

    params =
      case Keyword.fetch(opts, :expected_version) do
        {:ok, version} -> Map.put(params, "expected_configuration_version", version)
        :error -> params
      end

    %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "packet_bindings",
      "surfaceVersion" => 1,
      "actionId" => "save_packet_bindings",
      "scope" => scope_document(context),
      "input" => params
    }
  end

  defp revision_value(%{catalog_revision_id: value}), do: value

  defp endpoint_value(%{source_endpoint_id: value}), do: value

  defp scope_document(context, spacecraft_id \\ nil) do
    %{
      "organizationId" => context.organization.organization_id,
      "missionId" => context.mission.mission_id,
      "spacecraftId" => spacecraft_id || context.spacecraft.spacecraft_id
    }
  end

  defp bridge_conn(conn, catalog) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cadence-poc-session", catalog["session"]["sessionId"])
    |> put_req_header("x-csrf-token", catalog["session"]["csrfToken"])
  end

  defp post_json(conn, path, body), do: post(conn, path, Jason.encode!(body))
end
