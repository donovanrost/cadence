defmodule QaRestMissions do
  @moduledoc "Creates the two QA missions, catalogs and pending fleet changes over REST."

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

  def seed(client, organization_id) do
    Enum.reduce(@missions, client, fn mission, client ->
      {client, mission_id} = ensure_mission(client, organization_id, mission)
      client = ensure_catalog(client, mission_id, mission)
      client = ensure_fleet(client, mission_id, mission)

      client =
        if mission.slug == "qa-mission-23565",
          do: ensure_provider(client, organization_id, mission_id),
          else: client

      IO.puts("  #{mission.slug}: mission and catalog present")
      client
    end)
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

  defp ensure_fleet(client, mission_id, mission) do
    path = "/missions/#{mission_id}/config"
    {client, directory} = request!(client, :get, "/missions/#{mission_id}/spacecraft")
    present = MapSet.new(Enum.map(directory["spacecraft"], & &1["id"]))
    required = Enum.map(mission.craft, fn {index, _scid} -> craft_id(mission, index) end)
    {client, config} = request!(client, :get, path)

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
