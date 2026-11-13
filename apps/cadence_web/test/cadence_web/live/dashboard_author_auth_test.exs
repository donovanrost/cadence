defmodule CadenceWeb.DashboardAuthorAuthTest do
  @moduledoc "L8a: a non-author is sent to the console's dashboards directory, not the legacy one."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.{DashboardAuthorAuth, TestFixtures}

  test "the console directory comes from the organization's and mission's slugs" do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)

    assert DashboardAuthorAuth.console_directory(org.organization_id, mission.mission_id) ==
             "/console/#{org.slug}/#{mission.slug}/telemetry/dashboards"
  end

  test "another organization's mission, or no organization, falls back to /console" do
    org = TestFixtures.persist_org!()
    other = TestFixtures.persist_mission!(TestFixtures.persist_org!())

    assert DashboardAuthorAuth.console_directory(org.organization_id, other.mission_id) ==
             "/console"

    assert DashboardAuthorAuth.console_directory(nil, other.mission_id) == "/console"
  end
end
