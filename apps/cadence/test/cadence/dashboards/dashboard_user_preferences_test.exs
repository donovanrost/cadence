defmodule Cadence.Dashboards.DashboardUserPreferencesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{User, UserRow}
  alias Cadence.Dashboards
  alias Cadence.Dashboards.Document
  alias Cadence.Ids

  setup do
    organization_id = Ids.new("org")
    mission_id = Ids.new("mission")
    %{mission: mission} = persist_mission_scope(organization_id, mission_id)

    user =
      User.new(%{
        email: "dashboard-preferences-#{System.unique_integer([:positive])}@example.test",
        display_name: "Dashboard Preferences",
        confirmed_at: DateTime.utc_now()
      })

    Repo.insert!(UserRow.changeset(user))

    %{organization_id: organization_id, mission: mission, user: user}
  end

  test "stars and recents are scoped to one user, organization, and mission", context do
    first = persist_dashboard!(context, "Power")
    second = persist_dashboard!(context, "Thermal")
    observed_at = ~U[2026-08-01 12:00:00Z]

    assert {:ok, starred} =
             Dashboards.set_dashboard_starred(
               context.organization_id,
               context.mission.mission_id,
               context.user.user_id,
               first.dashboard_id,
               true,
               observed_at: observed_at
             )

    assert starred.starred

    assert {:ok, recent} =
             Dashboards.record_dashboard_view(
               context.organization_id,
               context.mission.mission_id,
               context.user.user_id,
               second.dashboard_id,
               observed_at: DateTime.add(observed_at, 60, :second)
             )

    assert DateTime.compare(recent.last_viewed_at, DateTime.add(observed_at, 60, :second)) == :eq

    summaries =
      Dashboards.list_dashboard_summaries(
        context.organization_id,
        context.mission.mission_id
      )

    assert %{starred: [%{dashboard_id: starred_id}], recent: [%{dashboard_id: recent_id}]} =
             Dashboards.dashboard_navigation(
               context.organization_id,
               context.mission.mission_id,
               context.user.user_id,
               summaries
             )

    assert starred_id == first.dashboard_id
    assert recent_id == second.dashboard_id

    other_user = persist_user!()

    assert %{starred: [], recent: []} =
             Dashboards.dashboard_navigation(
               context.organization_id,
               context.mission.mission_id,
               other_user.user_id,
               summaries
             )
  end

  test "navigation caps starred and recent groups at five dashboards", context do
    observed_at = ~U[2026-08-01 12:00:00Z]

    dashboards =
      for index <- 1..12 do
        persist_dashboard!(context, "Dashboard #{index}")
      end

    dashboards
    |> Enum.take(6)
    |> Enum.each(fn dashboard ->
      assert {:ok, _preference} =
               Dashboards.set_dashboard_starred(
                 context.organization_id,
                 context.mission.mission_id,
                 context.user.user_id,
                 dashboard.dashboard_id,
                 true,
                 observed_at: observed_at
               )
    end)

    dashboards
    |> Enum.drop(6)
    |> Enum.with_index()
    |> Enum.each(fn {dashboard, index} ->
      assert {:ok, _preference} =
               Dashboards.record_dashboard_view(
                 context.organization_id,
                 context.mission.mission_id,
                 context.user.user_id,
                 dashboard.dashboard_id,
                 observed_at: DateTime.add(observed_at, index, :second)
               )
    end)

    navigation =
      Dashboards.dashboard_navigation(
        context.organization_id,
        context.mission.mission_id,
        context.user.user_id,
        Dashboards.list_dashboard_summaries(
          context.organization_id,
          context.mission.mission_id
        )
      )

    assert length(navigation.starred) == 5
    assert length(navigation.recent) == 5
  end

  test "rejects a dashboard outside the supplied scope", context do
    assert {:error, :dashboard_not_found} =
             Dashboards.set_dashboard_starred(
               context.organization_id,
               context.mission.mission_id,
               context.user.user_id,
               "dashboard-missing",
               true
             )
  end

  test "dashboard summaries expose normalized document tags", context do
    _dashboard =
      persist_dashboard!(context, "Tagged", %{
        "tags" => ["  thermal ", "flight", "thermal", ""]
      })

    assert [%{tags: ["flight", "thermal"]}] =
             Dashboards.list_dashboard_summaries(
               context.organization_id,
               context.mission.mission_id
             )
  end

  defp persist_dashboard!(context, name, metadata \\ %{}) do
    document = %Document{
      dashboard_id: Ids.new("dashboard"),
      organization_id: context.organization_id,
      mission_id: context.mission.mission_id,
      name: name,
      metadata: metadata
    }

    assert {:ok, persisted} = Dashboards.persist_document(context.organization_id, document)
    persisted
  end

  defp persist_user! do
    user =
      User.new(%{
        email: "dashboard-preferences-other-#{System.unique_integer([:positive])}@example.test",
        display_name: "Other Dashboard User",
        confirmed_at: DateTime.utc_now()
      })

    Repo.insert!(UserRow.changeset(user))
    user
  end
end
