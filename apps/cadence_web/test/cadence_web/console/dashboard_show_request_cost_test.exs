defmodule CadenceWeb.Console.DashboardShowRequestCostTest do
  @moduledoc """
  #1058: what one `GET /dashboards/:id` costs, counted as the queries of the request (the Repo's
  telemetry, tasks included, `RequestCost`), for a dashboard of eight time-series widgets with the
  limits, events and quality overlays, over a relative window (so no source result is served from
  cache) and the persisted registry a deployment runs. The registry is read once per resolve (it
  was four times per source request and stage: 175 queries here, 132 of them the registry), and a
  re-observation of an unchanged source health writes nothing. The count is equal at 5 and at 50
  spacecraft and under a ceiling a few above today's 46.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Dashboards.{DocumentCodec, Documents}
  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../../cadence/test/fixtures/dashboards/time_series_with_limits.v1.json",
             __DIR__
           )
  @widgets 8
  @ceiling 55

  # A running deployment resolves its sources from the persisted registry (`persisted?: true`).
  setup do
    previous = Application.get_env(:cadence, :data_sources)
    Application.put_env(:cadence, :data_sources, persisted?: true)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :data_sources, previous),
        else: Application.delete_env(:cadence, :data_sources)
    end)
  end

  defp setup_dashboard(fleet) do
    # The registry as a running deployment has it: the managed sources and their bindings persisted.
    DataSources.ensure_default_managed_sources!()

    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    for i <- 1..fleet, do: TestFixtures.persist_spacecraft!(mission, display_name: "SC-#{i}")

    %{user: user, org: org, mission: mission, document: persist_dashboard(org, mission)}
  end

  defp persist_dashboard(org, mission) do
    base = DocumentCodec.load!(@fixture)
    [placement] = base.placements

    placements =
      for n <- 1..@widgets do
        widget = put_in(placement, [Access.key(:placement_id)], "placement_#{n}")
        update_in(widget, [Access.key(:layout)], &%{&1 | y: n * 4})
      end

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "dashboard-" <> Ecto.UUID.generate(),
        placements: placements
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    document
  end

  # The first show of any dashboard records what it observed of the mission's sources. The cost
  # that matters is a second, different dashboard's first show, once they are recorded.
  defp warm(c) do
    queries(c)
    %{c | document: persist_dashboard(c.org, c.mission)}
  end

  defp queries(c) do
    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get(
        "/api/v1/missions/#{c.mission.mission_id}/dashboards/#{c.document.dashboard_id}" <>
          "?from=now-6h&to=now"
      )

    assert json_response(conn, 200)
    conn.private.cadence_request_cost.queries
  end

  test "a dashboard show costs the same at 5 and at 50 spacecraft, under a ceiling" do
    five = 5 |> setup_dashboard() |> warm() |> queries()
    fifty = 50 |> setup_dashboard() |> warm() |> queries()

    assert five == fifty
    assert fifty <= @ceiling
  end
end
