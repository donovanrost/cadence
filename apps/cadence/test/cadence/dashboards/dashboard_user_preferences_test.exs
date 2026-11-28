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

    preferences =
      Dashboards.list_dashboard_user_preferences(
        context.organization_id,
        context.mission.mission_id,
        context.user.user_id
      )

    assert [
             %{dashboard_id: starred_id, starred: true},
             %{dashboard_id: recent_id, starred: false, last_viewed_at: %DateTime{}}
           ] = preferences

    assert starred_id == first.dashboard_id
    assert recent_id == second.dashboard_id

    other_user = persist_user!()

    assert [] =
             Dashboards.list_dashboard_user_preferences(
               context.organization_id,
               context.mission.mission_id,
               other_user.user_id
             )
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
