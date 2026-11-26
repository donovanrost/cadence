Code.require_file("rest_client.exs", __DIR__)
Code.require_file("earendil_dashboards.exs", __DIR__)

defmodule EarendilDashboardImport do
  @moduledoc "Import the Earendil dashboards and playlist through the public REST API."

  import EarendilRestClient, only: [request!: 3, request!: 4, sign_in: 3, select_organization: 2]

  @playlist_name "Earendil — Demo Rotation"

  def run(organization_id, mission_id) do
    base = System.get_env("BASE_URL") || "http://127.0.0.1:#{System.get_env("PORT", "4001")}"
    email = System.fetch_env!("CADENCE_ADMIN_EMAIL")
    password = System.fetch_env!("CADENCE_ADMIN_PASSWORD")
    {client, _session} = sign_in(base, email, password)
    {client, _session} = select_organization(client, organization_id)
    client = probe_source(client, mission_id)
    {_client, result} = import_documents(client, organization_id, mission_id)
    result
  end

  def import_documents(client, organization_id, mission_id) do
    path = "/missions/#{mission_id}/dashboards"
    documents = EarendilDashboardDocuments.documents(organization_id, mission_id)

    {dashboards, client} =
      Enum.map_reduce(documents, client, fn document, client ->
        {client, result} = request!(client, :post, path, %{document: document, identity: "keep"})

        unless result["id"] == document.dashboard_id,
          do: raise("dashboard import returned the wrong id: #{inspect(result)}")

        state = if result["existing"], do: "existing", else: "created"
        IO.puts("  #{document.dashboard_id}: #{state}")
        {%{id: document.dashboard_id, name: document.name}, client}
      end)

    {client, playlist} = ensure_playlist(client, mission_id, Enum.map(dashboards, & &1.id))
    {client, %{dashboards: dashboards, playlist: playlist}}
  end

  defp probe_source(client, mission_id) do
    path = "/missions/#{mission_id}/data-sources"
    {client, directory} = request!(client, :get, path)
    source = Enum.find(directory["sources"], &(&1["id"] == "managed_questdb_primary"))
    unless source, do: raise("managed QuestDB source is unavailable")

    {client, result} = request!(client, :post, path <> "/#{source["id"]}/probe", %{})
    IO.puts("  managed QuestDB: #{get_in(result, ["probe", "health", "status"]) || "unknown"}")
    client
  end

  defp ensure_playlist(client, mission_id, dashboard_ids) do
    path = "/missions/#{mission_id}/dashboard-playlists"
    {client, directory} = request!(client, :get, path)
    existing = Enum.find(directory["playlists"], &(&1["name"] == @playlist_name))

    if existing do
      IO.puts("  playlist #{existing["id"]}: existing")
      {client, existing["id"]}
    else
      {client, created} =
        request!(client, :post, path, %{
          name: @playlist_name,
          description: "Six live telemetry views for the ten-spacecraft rehearsal.",
          dashboard_ids: dashboard_ids,
          dwell_seconds: 30,
          wallboard_mode: true
        })

      IO.puts("  playlist #{created["id"]}: created")
      {client, created["id"]}
    end
  end
end
