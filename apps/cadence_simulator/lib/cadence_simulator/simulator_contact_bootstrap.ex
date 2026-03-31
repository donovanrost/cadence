defmodule CadenceSimulator.SimulatorContactBootstrap do
  @moduledoc """
  HTTP-only mission bootstrap flow for standing up a simulator-backed contact.

  This module is intentionally API-driven so it can run without starting the
  Cadence application in the current BEAM.
  """

  @default_base_url "http://127.0.0.1:4001"
  @default_downlink_provider_port 4100
  @bootstrap_admin_session_path "/bootstrap_admin/login"

  @spec run_from_env(keyword()) :: map()
  def run_from_env(opts \\ []) when is_list(opts) do
    run(env_config(), opts)
  end

  @spec run(map(), keyword()) :: map()
  def run(opts, runtime_opts \\ []) when is_map(opts) and is_list(runtime_opts) do
    config = normalize_config(opts)
    req_client = Keyword.get(runtime_opts, :req_client, Req)

    {api_token, organization_id, mission_id, issued_service_identity} =
      ensure_scope!(config, req_client)

    req = authed_req(req_client, config.base_url, api_token)

    spacecraft =
      ensure_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/#{config.spacecraft_id}",
        "/organizations/#{organization_id}/missions/#{mission_id}/spacecraft",
        "spacecraft",
        %{
          "spacecraft_id" => config.spacecraft_id,
          "display_name" => config.spacecraft_display_name
        }
      )

    source_endpoint =
      ensure_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/source_endpoints/#{config.source_endpoint_id}",
        "/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/#{config.spacecraft_id}/source_endpoints",
        "source_endpoint",
        %{
          "source_endpoint_id" => config.source_endpoint_id,
          "source_ref" => config.source_ref,
          "display_name" => config.source_endpoint_display_name
        }
      )

    import_result = import_catalog!(req_client, req, organization_id, mission_id, config)

    activation =
      maybe_materialize_and_activate!(req_client, req, organization_id, mission_id, import_result)

    provider_profile =
      ensure_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles/#{config.provider_profile_id}",
        "/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles",
        "provider_profile",
        %{
          "provider_profile_id" => config.provider_profile_id,
          "adapter_key" => "tcp_socket",
          "configuration" => %{
            "mode" => "listen",
            "port" => config.downlink_provider_port,
            "ingress_protocol_family" => "tm",
            "frame_size" => 1115,
            "ingress_metadata" => %{
              "frame_size" => 1115,
              "ocf_length" => 0
            }
          }
        }
      )

    transport_profile =
      ensure_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/transport_profiles/#{config.transport_profile_id}",
        "/organizations/#{organization_id}/missions/#{mission_id}/transport_profiles",
        "transport_profile",
        %{
          "transport_profile_id" => config.transport_profile_id,
          "family_key" => "uplink_gateway",
          "target_scope" => "path",
          "configuration" => %{"transport_profile" => "tc"}
        }
      )

    uplink_path_template =
      ensure_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/path_templates/#{config.uplink_path_template_id}",
        "/organizations/#{organization_id}/missions/#{mission_id}/path_templates",
        "path_template",
        %{
          "path_template_id" => config.uplink_path_template_id,
          "path_id" => config.uplink_path_id,
          "direction" => "uplink",
          "selection_role" => "selected",
          "source_endpoint_ref" => config.source_endpoint_id,
          "transport_profile_ids" => [config.transport_profile_id]
        }
      )

    downlink_path_template =
      ensure_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/path_templates/#{config.downlink_path_template_id}",
        "/organizations/#{organization_id}/missions/#{mission_id}/path_templates",
        "path_template",
        %{
          "path_template_id" => config.downlink_path_template_id,
          "path_id" => config.downlink_path_id,
          "direction" => "downlink",
          "selection_role" => "selected",
          "source_endpoint_ref" => config.source_endpoint_id,
          "provider_profile_ids" => [config.provider_profile_id]
        }
      )

    {scheduled_contact, realized_contact} =
      case maybe_active_realized_contact(req_client, req, organization_id, mission_id, config) do
        %{} = active_realized_contact ->
          scheduled_contact_id = Map.fetch!(active_realized_contact, "scheduled_contact_id")

          {
            get_json!(
              req_client,
              req,
              "/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts/#{scheduled_contact_id}"
            ),
            active_realized_contact
          }

        nil ->
          starts_at = DateTime.add(DateTime.utc_now(), config.contact_start_delay_seconds, :second)
          ends_at = DateTime.add(starts_at, config.contact_duration_seconds, :second)
          scheduled_contact_id = generated_scheduled_contact_id(config)

          scheduled_contact =
            post_resource!(
              req_client,
              req,
              "/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts",
              "scheduled_contact",
              %{
                "scheduled_contact_id" => scheduled_contact_id,
                "source_endpoint_refs" => [config.source_endpoint_id],
                "path_template_ids" => [
                  config.uplink_path_template_id,
                  config.downlink_path_template_id
                ],
                "starts_at" => DateTime.to_iso8601(starts_at),
                "ends_at" => DateTime.to_iso8601(ends_at),
                "provider_contact_ref" => config.provider_contact_ref
              }
            )

          realized_contact =
            if config.realize_contact? do
              post_json!(
                req_client,
                req,
                "/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts/#{scheduled_contact_id}/realize",
                %{"realization" => %{"clock_mode" => "live"}}
              )
            else
              nil
            end

          {scheduled_contact, realized_contact}
      end

    summary = %{
      effective_config: config,
      organization_id: organization_id,
      mission_id: mission_id,
      api_token: api_token,
      issued_service_identity: issued_service_identity,
      spacecraft: spacecraft,
      source_endpoint: source_endpoint,
      import_result: import_result,
      activation: activation,
      provider_profile: provider_profile,
      transport_profile: transport_profile,
      uplink_path_template: uplink_path_template,
      downlink_path_template: downlink_path_template,
      scheduled_contact: scheduled_contact,
      realized_contact: realized_contact
    }

    if Keyword.get(runtime_opts, :print_summary?, true) do
      print_summary(config, summary)
    end

    summary
  end

  defp ensure_scope!(%{api_token: api_token} = config, _req_client)
       when is_binary(api_token) and api_token != "" do
    {api_token, config.organization_id, config.mission_id, nil}
  end

  defp ensure_scope!(config, req_client) do
    bootstrap_admin_session_token = login_bootstrap_admin!(config, req_client)
    bootstrap_req = authed_req(req_client, config.base_url, bootstrap_admin_session_token)

    payload = %{
      "bootstrap" => %{
        "organization" => %{
          "organization_id" => config.organization_id,
          "slug" => config.organization_slug,
          "display_name" => config.organization_display_name
        },
        "mission" => %{
          "mission_id" => config.mission_id,
          "slug" => config.mission_slug,
          "display_name" => config.mission_display_name
        },
        "service_identity" => %{
          "service_identity_id" => config.service_identity_id,
          "display_name" => config.service_identity_display_name
        }
      }
    }

    response = req_client.post!(bootstrap_req, url: "/bootstrap", json: payload)

    case response.status do
      201 ->
        data = Map.fetch!(response.body, "data")
        service_identity = Map.fetch!(data, "service_identity")
        bootstrap_api_token = Map.fetch!(service_identity, "api_token")

        issued_service_identity =
          maybe_issue_mission_service_identity!(req_client, config, bootstrap_api_token)

        effective_api_token =
          issued_service_identity
          |> Kernel.||(service_identity)
          |> Map.fetch!("api_token")

        {effective_api_token, config.organization_id, config.mission_id, issued_service_identity}

      409 ->
        {bootstrap_admin_session_token, config.organization_id, config.mission_id, nil}

      status ->
        raise """
        bootstrap failed with status #{status}: #{inspect(response.body)}
        """
    end
  end

  defp maybe_issue_mission_service_identity!(req_client, config, bootstrap_api_token) do
    if config.issue_mission_token? do
      mission_req = authed_req(req_client, config.base_url, bootstrap_api_token)

      maybe_post_resource(
        req_client,
        mission_req,
        "/organizations/#{config.organization_id}/service_identities",
        "service_identity",
        %{
          "service_identity_id" => config.mission_service_identity_id,
          "mission_id" => config.mission_id,
          "display_name" => config.mission_service_identity_display_name,
          "capabilities" => ["mission_admin"]
        }
      )
      |> case do
        {:ok, service_identity} -> service_identity
        {:error, 409, _body} -> nil
        {:error, status, body} -> raise "service identity request failed with status #{status}: #{inspect(body)}"
      end
    else
      nil
    end
  end

  defp import_catalog!(req_client, req, organization_id, mission_id, config) do
    suffix = unique_suffix()
    artifact_id = "artifact-" <> config.mission_id <> "-" <> suffix
    import_run_id = "import-run-" <> config.mission_id <> "-" <> suffix

    source_artifact =
      config.definitions_path
      |> Path.expand()
      |> File.read!()

    artifact =
      post_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts",
        "catalog_artifact",
        %{
          "artifact_id" => artifact_id,
          "artifact_name" => Path.basename(config.definitions_path),
          "catalog_family" => "combined",
          "format_key" => "cadence_yaml",
          "media_type" => "application/yaml",
          "source_artifact" => source_artifact
        }
      )

    import_run =
      post_resource!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs",
        "catalog_import_run",
        %{
          "import_run_id" => import_run_id,
          "artifact_id" => artifact_id,
          "importer_key" => "cadence_yaml"
        }
      )

    completed_import_run =
      wait_for_import_run!(
        req_client,
        req,
        organization_id,
        mission_id,
        Map.fetch!(import_run, "import_run_id")
      )

    %{
      artifact: artifact,
      import_run: completed_import_run,
      telemetry_snapshot_id:
        telemetry_snapshot_id(completed_import_run) ||
          Map.get(completed_import_run, "snapshot_id"),
      command_snapshot_id: command_snapshot_id(completed_import_run)
    }
  end

  defp maybe_materialize_and_activate!(
         _req_client,
         _req,
         _organization_id,
         _mission_id,
         %{telemetry_snapshot_id: nil}
       ),
       do: nil

  defp maybe_materialize_and_activate!(
         req_client,
         req,
         organization_id,
         mission_id,
         import_result
       ) do
    materialized =
      post_json!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots/#{import_result.telemetry_snapshot_id}/materialize_runtime",
        %{}
      )

    binding_set = Map.get(materialized, "binding_set")

    activation =
      if is_map(binding_set) do
        post_resource!(
          req_client,
          req,
          "/organizations/#{organization_id}/missions/#{mission_id}/activations",
          "activation",
          %{
            "binding_set_id" => Map.fetch!(binding_set, "binding_set_id"),
            "version" => Map.fetch!(binding_set, "version")
          }
        )
      else
        nil
      end

    %{materialized_runtime: materialized, activation: activation}
  end

  defp wait_for_import_run!(req_client, req, organization_id, mission_id, import_run_id) do
    deadline = System.monotonic_time(:millisecond) + 30_000
    do_wait_for_import_run(req_client, req, organization_id, mission_id, import_run_id, deadline)
  end

  defp do_wait_for_import_run(
         req_client,
         req,
         organization_id,
         mission_id,
         import_run_id,
         deadline
       ) do
    import_run =
      get_json!(
        req_client,
        req,
        "/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    case Map.get(import_run, "status") do
      "completed" ->
        import_run

      "failed" ->
        raise "catalog import failed: #{inspect(import_run)}"

      _other ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "catalog import timed out waiting for completion: #{inspect(import_run)}"
        else
          Process.sleep(500)

          do_wait_for_import_run(
            req_client,
            req,
            organization_id,
            mission_id,
            import_run_id,
            deadline
          )
        end
    end
  end

  defp print_summary(config, summary) do
    realized_contact_id =
      summary.realized_contact && Map.get(summary.realized_contact, "realized_contact_id")

    api_token = summary.api_token

    issued_service_identity_id =
      get_in(summary, [:issued_service_identity, "service_identity", "service_identity_id"]) ||
        "(using provided/bootstrap token)"

    IO.puts("""
    Bootstrapped simulator contact:
      organization_id: #{summary.organization_id}
      mission_id: #{summary.mission_id}
      service_identity_id: #{issued_service_identity_id}
      spacecraft_id: #{summary.spacecraft["spacecraft_id"]}
      source_endpoint_id: #{summary.source_endpoint["source_endpoint_id"]}
      scheduled_contact_id: #{summary.scheduled_contact["scheduled_contact_id"]}
      realized_contact_id: #{realized_contact_id || "(not realized)"}
      telemetry_snapshot_id: #{summary.import_result.telemetry_snapshot_id || "(none)"}
      command_snapshot_id: #{summary.import_result.command_snapshot_id || "(none)"}

    Telemetry simulator:
      cadence_simulator telemetry \\
        --definitions #{config.definitions_path} \\
        --cadence-url #{config.base_url} \\
        --api-token #{api_token} \\
        --organization-id #{summary.organization_id} \\
        --mission-id #{summary.mission_id} \\
        --realized-contact-id #{realized_contact_id || config.scheduled_contact_id <> "_run"} \\
        --path-id #{config.downlink_path_id}

    COP-1 loopback:
      cadence_simulator cop1_loopback \\
        --cadence-url #{config.base_url} \\
        --api-token #{api_token} \\
        --organization-id #{summary.organization_id} \\
        --mission-id #{summary.mission_id} \\
        --realized-contact-id #{realized_contact_id || config.scheduled_contact_id <> "_run"} \\
        --path-id #{config.uplink_path_id} \\
        --transport-binding-id #{config.transport_profile_id}
    """)
  end

  defp login_bootstrap_admin!(config, req_client) do
    credentials =
      %{
        "email" => config.bootstrap_admin_email,
        "password" => config.bootstrap_admin_password
      }

    if Enum.any?(credentials, fn {_key, value} -> is_nil(value) or value == "" end) do
      raise """
      bootstrap admin credentials are required when no API token is provided. Set \
      CADENCE_BOOTSTRAP_ADMIN_ENABLED=true together with \
      CADENCE_BOOTSTRAP_ADMIN_EMAIL and CADENCE_BOOTSTRAP_ADMIN_PASSWORD.
      """
    end

    response =
      req_client.post!(
        req(req_client, config.base_url),
        url: @bootstrap_admin_session_path,
        json: %{"bootstrap_admin_session" => credentials}
      )

    case response.status do
      status when status in 200..299 ->
        response.body
        |> Map.fetch!("data")
        |> Map.fetch!("session_token")

      status ->
        raise "bootstrap admin login failed with status #{status}: #{inspect(response.body)}"
    end
  end

  defp post_resource!(req_client, req, path, key, payload) do
    post_json!(req_client, req, path, %{key => payload})
  end

  defp maybe_post_resource(req_client, req, path, key, payload) do
    maybe_post_json(req_client, req, path, %{key => payload})
  end

  defp ensure_resource!(req_client, req, fetch_path, create_path, key, payload) do
    case maybe_get_json(req_client, req, fetch_path) do
      {:ok, data} ->
        data

      {:error, 404, _body} ->
        post_resource!(req_client, req, create_path, key, payload)

      {:error, status, body} ->
        raise "request failed with status #{status}: #{inspect(body)}"
    end
  end

  defp post_json!(req_client, req, path, payload) do
    case maybe_post_json(req_client, req, path, payload) do
      {:ok, data} -> data
      {:error, status, body} -> raise "request failed with status #{status}: #{inspect(body)}"
    end
  end

  defp get_json!(req_client, req, path) do
    case maybe_get_json(req_client, req, path) do
      {:ok, data} -> data
      {:error, status, body} -> raise "request failed with status #{status}: #{inspect(body)}"
    end
  end

  defp maybe_post_json(req_client, req, path, payload) do
    response = req_client.post!(req, url: path, json: payload)
    response_data(response)
  end

  defp maybe_get_json(req_client, req, path) do
    response = req_client.get!(req, url: path)
    response_data(response)
  end

  defp response_data(response) do
    case response.status do
      status when status in 200..299 ->
        {:ok, Map.fetch!(response.body, "data")}

      status ->
        {:error, status, response.body}
    end
  end

  defp maybe_active_realized_contact(req_client, req, organization_id, mission_id, config) do
    if config.reuse_active_contact? do
      req_client
      |> get_json!(req, "/organizations/#{organization_id}/missions/#{mission_id}/realized_contacts")
      |> Enum.filter(&realized_contact_active?/1)
      |> Enum.find(fn realized_contact ->
        realized_contact_matches_profile?(realized_contact, config) &&
          path_runtime_running?(
            req_client,
            req,
            organization_id,
            mission_id,
            Map.fetch!(realized_contact, "realized_contact_id"),
            config.downlink_path_id
          )
      end)
    else
      nil
    end
  end

  defp realized_contact_active?(%{"lifecycle_state" => "active"}), do: true
  defp realized_contact_active?(_realized_contact), do: false

  defp realized_contact_matches_profile?(%{"paths" => paths}, config) when is_list(paths) do
    Enum.any?(paths, fn path ->
      Map.get(path, "path_id") == config.downlink_path_id &&
        Map.get(path, "source_endpoint_ref") == config.source_endpoint_id
    end)
  end

  defp realized_contact_matches_profile?(_realized_contact, _config), do: false

  defp path_runtime_running?(
         req_client,
         req,
         organization_id,
         mission_id,
         realized_contact_id,
         path_id
       ) do
    case maybe_get_json(
           req_client,
           req,
           "/organizations/#{organization_id}/missions/#{mission_id}/realized_contacts/#{realized_contact_id}/paths/#{path_id}/runtime"
         ) do
      {:ok, _runtime_snapshot} -> true
      {:error, 404, _body} -> false
      {:error, 422, _body} -> false
      {:error, status, body} -> raise "request failed with status #{status}: #{inspect(body)}"
    end
  end

  defp generated_scheduled_contact_id(config) do
    base =
      config.scheduled_contact_id ||
        "contact-" <> (config.profile_name || config.mission_id || "dev")

    base <> "-" <> unique_suffix()
  end

  defp unique_suffix do
    System.system_time(:second)
    |> Integer.to_string(36)
  end

  defp telemetry_snapshot_id(import_run) when is_map(import_run) do
    import_run
    |> get_in(["result_document", "telemetry_snapshot", "snapshot_id"])
    |> Kernel.||(get_in(import_run, ["result_document", "snapshot", "snapshot_id"]))
  end

  defp command_snapshot_id(import_run) when is_map(import_run) do
    get_in(import_run, ["result_document", "command_snapshot", "snapshot_id"])
  end

  defp req(req_client, base_url) do
    req_client.new(
      base_url: api_base_url(base_url),
      headers: [{"content-type", "application/json"}]
    )
  end

  defp authed_req(req_client, base_url, api_token) do
    req_client.new(
      base_url: api_base_url(base_url),
      headers: [
        {"authorization", "Bearer " <> api_token},
        {"content-type", "application/json"}
      ]
    )
  end

  defp api_base_url(base_url) do
    normalized = String.trim_trailing(base_url, "/")

    if String.ends_with?(normalized, "/api") do
      normalized
    else
      normalized <> "/api"
    end
  end

  defp normalize_config(opts) do
    normalized_opts = canonicalize_option_keys(opts)

    %{
      base_url: @default_base_url,
      organization_id: "org-alpha",
      organization_slug: "org-alpha",
      organization_display_name: "Org Alpha",
      mission_id: "mission-alpha",
      mission_slug: "mission-alpha",
      mission_display_name: "Mission Alpha",
      service_identity_id: "svc-bootstrap",
      service_identity_display_name: "Bootstrap Service",
      spacecraft_id: "spacecraft-001",
      spacecraft_display_name: "SC-001",
      source_endpoint_id: "source-endpoint-001",
      source_ref: "sc-001",
      source_endpoint_display_name: "SC-001 Primary Endpoint",
      definitions_path: default_definitions_path(),
      provider_profile_id: "tcp-downlink-profile",
      transport_profile_id: "uplink-gateway-profile",
      downlink_path_template_id: "downlink-template-alpha",
      uplink_path_template_id: "uplink-template-alpha",
      downlink_path_id: "downlink-path-alpha",
      uplink_path_id: "uplink-path-alpha",
      scheduled_contact_id: "contact-alpha",
      provider_contact_ref: "provider-contact-001",
      bootstrap_admin_email: System.get_env("CADENCE_BOOTSTRAP_ADMIN_EMAIL"),
      bootstrap_admin_password: System.get_env("CADENCE_BOOTSTRAP_ADMIN_PASSWORD"),
      downlink_provider_port: @default_downlink_provider_port,
      contact_start_delay_seconds: 60,
      contact_duration_seconds: 600,
      realize_contact?: true,
      issue_mission_token?: true,
      reuse_active_contact?: true
    }
    |> Map.merge(normalized_opts)
    |> put_dynamic_default(
      :mission_service_identity_id,
      &("svc-simulator-" <> &1.mission_id)
    )
    |> put_dynamic_default(
      :mission_service_identity_display_name,
      &"#{&1.mission_display_name} Simulator Service"
    )
  end

  defp put_dynamic_default(config, key, fun)
       when is_map(config) and is_atom(key) and is_function(fun, 1) do
    case Map.get(config, key) do
      nil -> Map.put(config, key, fun.(config))
      "" -> Map.put(config, key, fun.(config))
      _other -> config
    end
  end

  defp env_config do
    %{
      base_url: System.get_env("CADENCE_BASE_URL", @default_base_url),
      api_token: System.get_env("CADENCE_API_TOKEN"),
      organization_id: System.get_env("CADENCE_ORGANIZATION_ID", "org-alpha"),
      organization_slug: System.get_env("CADENCE_ORGANIZATION_SLUG", "org-alpha"),
      organization_display_name: System.get_env("CADENCE_ORGANIZATION_DISPLAY_NAME", "Org Alpha"),
      mission_id: System.get_env("CADENCE_MISSION_ID", "mission-alpha"),
      mission_slug: System.get_env("CADENCE_MISSION_SLUG", "mission-alpha"),
      mission_display_name: System.get_env("CADENCE_MISSION_DISPLAY_NAME", "Mission Alpha"),
      service_identity_id: System.get_env("CADENCE_SERVICE_IDENTITY_ID", "svc-bootstrap"),
      service_identity_display_name:
        System.get_env("CADENCE_SERVICE_IDENTITY_DISPLAY_NAME", "Bootstrap Service"),
      mission_service_identity_id: System.get_env("CADENCE_MISSION_SERVICE_IDENTITY_ID"),
      mission_service_identity_display_name:
        System.get_env("CADENCE_MISSION_SERVICE_IDENTITY_DISPLAY_NAME"),
      spacecraft_id: System.get_env("CADENCE_SPACECRAFT_ID", "spacecraft-001"),
      spacecraft_display_name: System.get_env("CADENCE_SPACECRAFT_DISPLAY_NAME", "SC-001"),
      source_endpoint_id: System.get_env("CADENCE_SOURCE_ENDPOINT_ID", "source-endpoint-001"),
      source_ref: System.get_env("CADENCE_SOURCE_REF", "sc-001"),
      source_endpoint_display_name:
        System.get_env("CADENCE_SOURCE_ENDPOINT_DISPLAY_NAME", "SC-001 Primary Endpoint"),
      definitions_path: System.get_env("CADENCE_DEFINITIONS_PATH", default_definitions_path()),
      provider_profile_id: System.get_env("CADENCE_PROVIDER_PROFILE_ID", "tcp-downlink-profile"),
      transport_profile_id:
        System.get_env("CADENCE_TRANSPORT_PROFILE_ID", "uplink-gateway-profile"),
      downlink_path_template_id:
        System.get_env("CADENCE_DOWNLINK_PATH_TEMPLATE_ID", "downlink-template-alpha"),
      uplink_path_template_id:
        System.get_env("CADENCE_UPLINK_PATH_TEMPLATE_ID", "uplink-template-alpha"),
      downlink_path_id: System.get_env("CADENCE_DOWNLINK_PATH_ID", "downlink-path-alpha"),
      uplink_path_id: System.get_env("CADENCE_UPLINK_PATH_ID", "uplink-path-alpha"),
      scheduled_contact_id: System.get_env("CADENCE_SCHEDULED_CONTACT_ID", "contact-alpha"),
      provider_contact_ref:
        System.get_env("CADENCE_PROVIDER_CONTACT_REF", "provider-contact-001"),
      bootstrap_admin_email: System.get_env("CADENCE_BOOTSTRAP_ADMIN_EMAIL"),
      bootstrap_admin_password: System.get_env("CADENCE_BOOTSTRAP_ADMIN_PASSWORD"),
      downlink_provider_port:
        env_integer("CADENCE_DOWNLINK_PROVIDER_PORT", @default_downlink_provider_port),
      contact_start_delay_seconds: env_integer("CADENCE_CONTACT_START_DELAY_SECONDS", 60),
      contact_duration_seconds: env_integer("CADENCE_CONTACT_DURATION_SECONDS", 600),
      realize_contact?: env_boolean("CADENCE_REALIZE_CONTACT", true),
      issue_mission_token?: env_boolean("CADENCE_ISSUE_MISSION_TOKEN", true),
      reuse_active_contact?: env_boolean("CADENCE_REUSE_ACTIVE_CONTACT", true)
    }
  end

  defp canonicalize_option_keys(opts) when is_map(opts) do
    Enum.reduce(opts, %{}, fn {key, value}, acc ->
      canonical_key =
        case key do
          :cadence_url -> :base_url
          "cadence_url" -> :base_url
          "base_url" -> :base_url
          "api_token" -> :api_token
          "organization_id" -> :organization_id
          "organization_slug" -> :organization_slug
          "organization_display_name" -> :organization_display_name
          "mission_id" -> :mission_id
          "mission_slug" -> :mission_slug
          "mission_display_name" -> :mission_display_name
          "service_identity_id" -> :service_identity_id
          "service_identity_display_name" -> :service_identity_display_name
          "mission_service_identity_id" -> :mission_service_identity_id
          "mission_service_identity_display_name" -> :mission_service_identity_display_name
          "spacecraft_id" -> :spacecraft_id
          "spacecraft_display_name" -> :spacecraft_display_name
          "source_endpoint_id" -> :source_endpoint_id
          "source_ref" -> :source_ref
          "source_endpoint_display_name" -> :source_endpoint_display_name
          "definitions_path" -> :definitions_path
          "provider_profile_id" -> :provider_profile_id
          "transport_profile_id" -> :transport_profile_id
          "downlink_path_template_id" -> :downlink_path_template_id
          "uplink_path_template_id" -> :uplink_path_template_id
          "downlink_path_id" -> :downlink_path_id
          "uplink_path_id" -> :uplink_path_id
          "scheduled_contact_id" -> :scheduled_contact_id
          "provider_contact_ref" -> :provider_contact_ref
          "bootstrap_admin_email" -> :bootstrap_admin_email
          "bootstrap_admin_password" -> :bootstrap_admin_password
          "downlink_provider_port" -> :downlink_provider_port
          "contact_start_delay_seconds" -> :contact_start_delay_seconds
          "contact_duration_seconds" -> :contact_duration_seconds
          "profile_name" -> :profile_name
          :issue_mission_token -> :issue_mission_token?
          "issue_mission_token" -> :issue_mission_token?
          "issue_mission_token?" -> :issue_mission_token?
          :realize_contact -> :realize_contact?
          "realize_contact" -> :realize_contact?
          "realize_contact?" -> :realize_contact?
          :reuse_active_contact -> :reuse_active_contact?
          "reuse_active_contact" -> :reuse_active_contact?
          "reuse_active_contact?" -> :reuse_active_contact?
          atom when is_atom(atom) -> atom
          _other -> nil
        end

      if is_nil(canonical_key) do
        acc
      else
        Map.put(acc, canonical_key, value)
      end
    end)
  end

  defp default_definitions_path do
    Path.expand("../../../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml", __DIR__)
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> raise "invalid integer for #{name}: #{inspect(value)}"
        end
    end
  end

  defp env_boolean(name, default) do
    case System.get_env(name) do
      nil -> default
      value when value in ["1", "true", "TRUE", "yes", "YES"] -> true
      value when value in ["0", "false", "FALSE", "no", "NO"] -> false
      value -> raise "invalid boolean for #{name}: #{inspect(value)}"
    end
  end
end
