Code.require_file("rest_client.exs", __DIR__)

defmodule Cadence.Dev.RouteChanges do
  @moduledoc "Stages the development fixtures' routing changes through the Console API."

  import EarendilRestClient, only: [request!: 3, request!: 4]

  @batch_size 300

  def sign_in(organization_id) do
    base = System.get_env("BASE_URL") || "http://127.0.0.1:#{System.get_env("PORT", "4001")}"
    email = System.fetch_env!("CADENCE_ADMIN_EMAIL")
    password = System.fetch_env!("CADENCE_ADMIN_PASSWORD")
    {client, _session} = EarendilRestClient.sign_in(base, email, password)
    {client, _session} = EarendilRestClient.select_organization(client, organization_id)
    client
  end

  def extra_route_ids(client, mission_id, profile_id) do
    {_client, profile} = request!(client, :get, "/missions/#{mission_id}/profiles/#{profile_id}")
    MapSet.new(profile["extra_routes"], & &1["route_id"])
  end

  def route(id, spacecraft_id, station_id, transport_id, name, purpose, downlink, uplink) do
    %{
      kind: "spacecraft_route",
      action: "create",
      entity_id: id,
      document: %{
        spacecraft_id: spacecraft_id,
        ground_station_id: station_id,
        transport_id: transport_id,
        display_name: name,
        purpose_label: purpose,
        downlink: downlink,
        uplink: uplink
      }
    }
  end

  def submit(_client, _mission_id, _source, _summary, []), do: :applied

  def submit(client, mission_id, name, summary, ops) do
    path = "/missions/#{mission_id}/config"
    source = %{"kind" => "dev_seed", "name" => name}
    {client, set} = current_set(client, path, source)

    case set do
      %{"id" => id, "state" => "in_review", "version" => version} ->
        {:in_review, id, version}

      _ ->
        client = stage(client, path, source, summary, missing_ops(ops, set))
        {client, set} = current_set(client, path, source)

        {_, result} =
          request!(client, :post, "#{path}/change-sets/#{set["id"]}/submit", %{
            reason: summary,
            expected_version: set["version"]
          })

        case result do
          %{"state" => "in_review", "change_set_id" => id, "version" => version} ->
            {:in_review, id, version}

          %{"state" => "applied"} ->
            :applied
        end
    end
  end

  defp current_set(client, path, source) do
    {client, %{"change_set" => set}} = request!(client, :get, path)

    if set && Enum.any?(set["changes"], &(&1["source"] != source)) do
      raise "Change set #{set["id"]} contains other changes. Finish it in the console before rerunning the route seed."
    end

    {client, set}
  end

  defp missing_ops(ops, nil), do: ops

  defp missing_ops(ops, set) do
    staged =
      for change <- set["changes"], op <- change["ops"], into: MapSet.new(), do: op["entity_id"]

    Enum.reject(ops, &MapSet.member?(staged, &1.entity_id))
  end

  defp stage(client, path, source, summary, ops) do
    ops
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(client, fn batch, client ->
      {client, _staged} =
        request!(client, :post, path <> "/stage", %{summary: summary, source: source, ops: batch})

      client
    end)
  end
end
