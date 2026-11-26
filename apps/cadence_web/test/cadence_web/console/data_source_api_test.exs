defmodule CadenceWeb.Console.DataSourceAPITest do
  @moduledoc "D1 data sources."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures

  test "lists the mission's data sources with health, last data and credentials" do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    DataSources.ensure_default_managed_sources!()

    sources =
      user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{mission.mission_id}/data-sources")
      |> json_response(200)
      |> get_in(["data", "sources"])

    tsdb = Enum.find(sources, &(&1["id"] == "managed_questdb_primary"))

    assert %{
             "display_name" => "Telemetry store (QuestDB)",
             "kind" => "managed_tsdb",
             "owner" => "cadence",
             "status" => "active",
             "health" => nil,
             "last_received_at" => nil,
             "expected_interval_s" => nil,
             "stale" => nil,
             "credentials" => nil
           } = tsdb
  end
end
