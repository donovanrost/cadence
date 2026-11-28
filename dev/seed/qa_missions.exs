defmodule QaRestMissions do
  @moduledoc "Creates the two QA missions, catalogs and pending fleet changes over REST."

  alias EarendilRouteChanges, as: RouteChanges

  import EarendilRestClient, only: [request!: 3, request!: 4, request!: 5]

  @missions [
    %{
      slug: "qa-mission-23565",
      name: "QA mission 23565",
      profile: "profile-qa-23565",
      profile_name: "QA L10 profile",
      catalog: "qa-l10 demo copy",
      craft: [{1, 1}, {2, 2}]
    },
    %{
      slug: "qa-mission-23566",
      name: "QA mission 23566",
      profile: "profile-qa-23566",
      profile_name: "QA mission 23566 profile",
      catalog: "qa-23566 demo copy",
      craft: [{1, 601}]
    }
  ]
  @metadata %{"fixture" => "apogee-qa-mission-v1"}

  def seed(client, approver, organization_id) do
    Enum.reduce(@missions, client, fn mission, client ->
      {client, mission_id} = ensure_mission(client, organization_id, mission)
      client = ensure_catalog(client, mission_id, mission)
      client = ensure_fleet(client, approver, mission_id, mission)
      client = ensure_sources_and_apps(client, mission_id, mission)

      client =
        if mission.slug == "qa-mission-23565",
          do:
            client
            |> ensure_provider(organization_id, mission_id)
            |> ensure_direct_route(approver, mission_id, mission)
            |> ensure_relay(approver, mission_id, mission),
          else: client

      IO.puts("  #{mission.slug}: mission and catalog present")
      client
    end)
  end

  defp ensure_relay(client, approver, mission_id, mission) do
    delivery_craft = craft_id(mission, 1)
    origins = [craft_id(mission, 2)]
    {client, endpoints} =
      request!(client, :get, "/missions/#{mission_id}/spacecraft/#{delivery_craft}/source-endpoints")

    endpoint =
      Enum.find(endpoints, &(get_in(&1, ["metadata", "managed_by"]) == "spacecraft")) ||
        raise("QA relay source endpoint is missing for #{delivery_craft}")

    if get_in(endpoint, ["relay", "origin_spacecraft_ids"]) != origins do
      operation = %{
        kind: "source_endpoint",
        action: "update",
        entity_id: endpoint["source_endpoint_id"],
        changes: [%{path: "relay.origin_spacecraft_ids", value: origins}]
      }

      case RouteChanges.submit(client, mission_id, "qa-relay", "Declare QA relay origin", [operation]) do
        :applied -> :ok
        {:in_review, _, _} -> approve_change_set(client, approver, mission_id)
      end
    end

    client
  end

  defp ensure_mission(client, organization_id, mission) do
    path = "/organizations/#{organization_id}/missions"
    {client, listing} = request!(client, :get, path)
    found = Enum.find(listing["missions"], &(&1["slug"] == mission.slug))

    if found do
      {client, found["id"]}
    else
      {client, created} =
        request!(client, :post, path, %{name: mission.name, slug: mission.slug})

      {client, created["mission"]["id"]}
    end
  end

  defp ensure_catalog(client, mission_id, mission) do
    path = "/missions/#{mission_id}/catalog"
    {client, listing} = request!(client, :get, path)
    database = Enum.find(listing["databases"], &(&1["name"] == mission.catalog))

    if database do
      {client, selected} = request!(client, :get, path <> "?database_id=#{database["id"]}")

      if get_in(selected, ["database", "current_revision", "id"]) do
        client
      else
        start_catalog_import(client, path, mission, database["id"])
      end
    else
      start_catalog_import(client, path, mission, nil)
    end
  end

  defp start_catalog_import(client, path, mission, database_id) do
    source = Path.expand("../catalogs/demo_spacecraft.yaml", __DIR__) |> File.read!()

    fields = [
      file: {source, filename: "demo_spacecraft.yaml", content_type: "application/yaml"},
      revision_label: "QA demo catalog",
      revision_notes: "Synthetic QA mission catalog"
    ]

    fields =
      if database_id,
        do: Keyword.put(fields, :database_id, database_id),
        else: Keyword.put(fields, :name, mission.catalog)

    {client, response} = request!(client, :post, path <> "/imports", nil, multipart: fields)
    await_catalog(client, path, response["import_run_id"], 120)
  end

  defp await_catalog(_client, _path, _run_id, 0), do: raise("QA catalog import timed out")

  defp await_catalog(client, path, run_id, remaining) do
    {client, run} = request!(client, :get, path <> "/imports/#{run_id}")

    case run["status"] do
      "succeeded" ->
        client

      "failed" ->
        raise "QA catalog import failed: #{inspect(run["diagnostics"])}"

      _ ->
        Process.sleep(500)
        await_catalog(client, path, run_id, remaining - 1)
    end
  end

  defp ensure_fleet(client, approver, mission_id, mission) do
    path = "/missions/#{mission_id}/config"
    {client, directory} = request!(client, :get, "/missions/#{mission_id}/spacecraft")
    present = MapSet.new(Enum.map(directory["spacecraft"], & &1["id"]))
    required = Enum.map(mission.craft, fn {index, _scid} -> craft_id(mission, index) end)
    {client, config} = request!(client, :get, path)

    client =
      cond do
        Enum.all?(required, &MapSet.member?(present, &1)) ->
          client

        config["change_set"] ->
          IO.puts("  #{mission.slug}: an open configuration change set awaits review")
          client

        true ->
          ops = [profile_op(mission) | Enum.map(mission.craft, &craft_op(mission, &1))]
          {client, preview} = request!(client, :post, path <> "/preview", %{ops: ops})
          unless preview["verdict"] == "go", do: raise("QA fleet preview: #{inspect(preview)}")

          {client, stage} =
            request!(client, :post, path <> "/stage", %{
              summary: "Seed #{mission.name} profile and spacecraft",
              source: %{kind: "dev_seed", name: mission.slug},
              ops: ops
            })

          {client, result} =
            request!(client, :post, path <> "/change-sets/#{stage["change_set_id"]}/submit", %{
              reason: "Seed #{mission.name}",
              expected_version: stage["version"]
            })

          IO.puts("  #{mission.slug}: fleet change set #{result["state"]}")
          client
      end

    approve_change_set(client, approver, mission_id)
    client
  end

  defp approve_change_set(client, approver, mission_id) do
    path = "/missions/#{mission_id}/config"
    {client, %{"change_set" => set}} = request!(client, :get, path)

    set =
      if set && set["state"] == "open" do
        {_, submitted} =
          request!(client, :post, path <> "/change-sets/#{set["id"]}/submit", %{
            reason: "Seed QA fleet",
            expected_version: set["version"]
          })

        submitted
      else
        set
      end

    if set && set["state"] == "in_review" do
      {_, result} =
        request!(
          approver,
          :post,
          path <> "/change-sets/#{set["change_set_id"] || set["id"]}/review",
          %{
            decision: "approve",
            expected_version: set["version"]
          }
        )

      unless result["state"] == "applied", do: raise("QA fleet approval failed")
    end
  end

  defp ensure_sources_and_apps(client, mission_id, mission) do
    Enum.reduce(mission.craft, client, fn {index, _scid}, client ->
      id = craft_id(mission, index)
      path = "/missions/#{mission_id}/spacecraft/#{id}"
      {client, sources} = request!(client, :get, path <> "/source-endpoints")
      source_ref = "QA MISSION #{String.replace_prefix(mission.slug, "qa-mission-", "")}-#{index}"

      client =
        if Enum.any?(sources, &(&1["source_ref"] == source_ref)) do
          client
        else
          {client, _created} =
            request!(client, :post, path <> "/source-endpoints", %{
              source_endpoint: %{
                source_ref: source_ref,
                display_name: "#{source_ref} TT&C",
                metadata: @metadata
              }
            })

          client
        end

      {client, listing} = request!(client, :get, path <> "/apps")
      decom = Enum.find(listing["apps"], &(&1["key"] == "telemetry_decom"))

      if decom && decom["state"] == "installed" do
        client
      else
        {client, _installed} =
          request!(client, :post, path <> "/apps/telemetry_decom/install", %{})

        client
      end
    end)
  end

  defp ensure_direct_route(client, approver, mission_id, mission) do
    craft_id = craft_id(mission, 1)
    route_id = "spacecraft_route_#{craft_id}-direct"
    existing = RouteChanges.extra_route_ids(client, mission_id, mission.profile)

    if MapSet.member?(existing, route_id) do
      client
    else
      {client, %{"stations" => stations}} =
        request!(client, :get, "/missions/#{mission_id}/ground-stations")

      {client, %{"transports" => transports}} =
        request!(client, :get, "/missions/#{mission_id}/transports")

      station_id = "station-qa-23565-local"
      transport_id = "transport-qa-23565-direct"

      station_ops =
        if Enum.any?(stations, &(&1["id"] == station_id)) do
          []
        else
          [
            %{
              kind: "ground_station",
              action: "create",
              entity_id: station_id,
              document: %{
                display_name: "QA local test station",
                code: "QALOCAL",
                metadata: @metadata
              }
            }
          ]
        end

      transport_op =
        if Enum.any?(transports, &(&1["id"] == transport_id)) do
          %{
            kind: "transport",
            action: "update",
            entity_id: transport_id,
            changes: [%{path: "ground_station_id", value: station_id}]
          }
        else
          %{
            kind: "transport",
            action: "create",
            entity_id: transport_id,
            document: %{
              display_name: "QA direct TCP client",
              origin: "direct",
              transport_kind: "tcp_socket",
              direction_capability: "inbound",
              ground_station_id: station_id,
              configuration: %{
                mode: "connect",
                direction_capability: "inbound",
                host: "127.0.0.1",
                port: 47_991,
                framing_mode: "fixed_size",
                frame_size: 1115,
                tls_enabled: false
              },
              metadata: @metadata
            }
          }
        end

      route =
        RouteChanges.route(
          route_id,
          craft_id,
          station_id,
          transport_id,
          "QA direct downlink",
          "TT&C downlink",
          "primary",
          "none"
        )

      case RouteChanges.submit(
             client,
             mission_id,
             "qa-direct-route",
             "Seed QA local test downlink",
             station_ops ++ [transport_op, route]
           ) do
        :applied -> :ok
        {:in_review, _id, _version} -> approve_change_set(client, approver, mission_id)
      end

      client
    end
  end

  defp profile_op(mission) do
    %{
      kind: "spacecraft_profile",
      action: "create",
      entity_id: mission.profile,
      document: %{
        display_name: mission.profile_name,
        downlink_protocol: "tm",
        uplink_protocol: "tc",
        frame_parameters: %{frame_size: 1115, ocf_length: 0, fecf: false},
        applications: %{telemetry_decom: %{}},
        metadata: @metadata
      }
    }
  end

  defp craft_op(mission, {index, scid}) do
    %{
      kind: "spacecraft",
      action: "create",
      entity_id: craft_id(mission, index),
      document: %{
        display_name:
          "QA MISSION #{String.replace_prefix(mission.slug, "qa-mission-", "")}-#{index}",
        scid: scid,
        spacecraft_type_id: mission.profile,
        spacecraft_type_version: 1,
        metadata: @metadata
      }
    }
  end

  defp craft_id(mission, index),
    do: "spacecraft-#{String.replace_prefix(mission.slug, "qa-mission-", "qa-")}-#{index}"

  defp ensure_provider(client, organization_id, mission_id) do
    path = "/organizations/#{organization_id}/provider-accounts"
    {client, listing} = request!(client, :get, path)
    account = Enum.find(listing["accounts"], &(&1["name"] == "QA simulator provider"))

    {client, account_id} =
      if account do
        {client, account["id"]}
      else
        {client, created} =
          request!(client, :post, path, %{
            provider_key: "simulator",
            name: "QA simulator provider",
            settings: %{
              base_url: System.fetch_env!("EARENDIL_PROVIDER_URL"),
              environment_ref: "run-earendil-demo-v1",
              event_ingestion_mode: "disabled"
            },
            credential: %{backend: "env", key: "EARENDIL_DEMO_PROVIDER_TOKEN"}
          })

        {client, created["id"]}
      end

    {client, detail} = request!(client, :get, path <> "/#{account_id}")

    grant =
      Enum.find(detail["grants"], fn row ->
        row["state"] == "active" and row["mission"]["id"] == mission_id
      end)

    {client, grant_id} =
      if grant do
        {client, grant["id"]}
      else
        {client, created} =
          request!(client, :post, path <> "/#{account_id}/grants", %{
            mission_id: mission_id,
            expected_account_version: detail["account"]["version"],
            reason: "Synthetic QA provider"
          })

        {client, created["grant"]["id"]}
      end

    provider_path = "/missions/#{mission_id}/providers"
    {client, listing} = request!(client, :get, provider_path)
    provider = Enum.find(listing["providers"], &(&1["name"] == "QA simulator provider"))

    {client, provider_id} =
      if provider do
        {client, provider["id"]}
      else
        {client, created} =
          request!(client, :post, provider_path, %{
            grant_id: grant_id,
            display_name: "QA simulator provider",
            policy_mode: "approval_required"
          })

        {client, created["provider"]["id"]}
      end

    {client, validate} = request!(client, :post, provider_path <> "/#{provider_id}/validate", %{})

    unless validate["result"]["ok"],
      do: raise("QA provider validation failed: #{inspect(validate)}")

    {client, sync} = request!(client, :post, provider_path <> "/#{provider_id}/sync", %{})
    unless sync["result"]["ok"], do: raise("QA provider sync failed: #{inspect(sync)}")
    client
  end
end
