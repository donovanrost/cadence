Mix.install([:req, :jason])
Code.require_file("rest_client.exs", __DIR__)
Code.require_file("invitations.exs", __DIR__)
Code.require_file("qa_personas.exs", __DIR__)
Code.require_file("planning.exs", __DIR__)
Code.require_file("route_changes.exs", __DIR__)
Code.require_file("qa_missions.exs", __DIR__)

defmodule QaRestSeed do
  @moduledoc false

  import EarendilRestClient, only: [request!: 3, sign_in: 3, select_organization: 2]

  def run do
    started = now()
    base = System.get_env("BASE_URL") || "http://127.0.0.1:#{System.get_env("PORT", "4001")}"

    {client, _session} =
      phase("QA admin session", fn ->
        sign_in(
          base,
          System.fetch_env!("CADENCE_ADMIN_EMAIL"),
          System.fetch_env!("CADENCE_ADMIN_PASSWORD")
        )
      end)

    {client, organization_id, mission_id} = phase("QA scope", fn -> scope(client) end)
    client = phase("QA personas", fn -> QaRestPersonas.seed(client, organization_id) end)

    {client, approver} =
      EarendilInvitations.ensure_person(
        client,
        organization_id,
        "qa-org-admin-2@example.com",
        "organization_admin",
        "QA Org Admin 2"
      )

    client = phase("QA planning", fn -> QaRestPlanning.seed(client, approver, mission_id) end)
    phase("QA missions", fn -> QaRestMissions.seed(client, approver, organization_id) end)
    IO.puts("QA REST seed total: #{elapsed(started)}")
  end

  defp scope(client) do
    {client, listing} = request!(client, :get, "/admin/organizations?q=reflect-orbital")

    organization =
      Enum.find(listing["organizations"], &(&1["slug"] == "reflect-orbital")) ||
        raise "Run the Earendil REST seed first (Reflect Orbital is missing)"

    organization_id = organization["id"]
    {client, session} = select_organization(client, organization_id)
    selected = Enum.find(session["organizations"], &(&1["id"] == organization_id))

    mission =
      Enum.find(selected["missions"], &(&1["slug"] == "earendil")) ||
        raise "Run the Earendil REST seed first (Earendil mission is missing)"

    {client, organization_id, mission["id"]}
  end

  defp phase(name, fun) do
    started = now()
    result = fun.()
    IO.puts("#{name}: #{elapsed(started)}")
    result
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(started), do: "#{Float.round((now() - started) / 1_000, 2)}s"
end

QaRestSeed.run()
