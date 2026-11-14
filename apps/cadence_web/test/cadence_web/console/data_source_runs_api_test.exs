defmodule CadenceWeb.Console.DataSourceRunsAPITest do
  @moduledoc """
  qa's L11 live writes (11-14): rotating to a new credential reference (B), a run's error as
  {code, message} (C), and Retry answering the run (D). docs/apogee/api/setup.md §Data sources.
  """
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Jobs
  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    %{org: org, user: user, mission: mission, conn: TestFixtures.member_conn(user)}
  end

  test "W5 rotates to a new reference; the same reference gets a new version (B)", c do
    source = register_byo!(c, "Mission QuestDB", "secret://l11-runs/first")

    assert %{"data" => %{"source" => %{"id" => id}}} =
             c.conn
             |> post(api(c, "/data-sources/#{source["id"]}/credential"), %{
               "credentials_ref" => "secret://l11-runs/second"
             })
             |> json_response(200)

    assert {:ok, %{credentials_ref: "secret://l11-runs/second"}} =
             DataSources.fetch_data_source(id)

    assert {:ok, %{credential_version: 1}} =
             DataSources.fetch_credential_reference("secret://l11-runs/second")

    c.conn
    |> post(api(c, "/data-sources/#{id}/credential"), %{
      "credentials_ref" => "secret://l11-runs/second"
    })
    |> json_response(200)

    assert {:ok, %{credential_version: 2}} =
             DataSources.fetch_credential_reference("secret://l11-runs/second")

    # Another source's reference isn't this source's to take.
    other = register_byo!(c, "Other QuestDB", "secret://l11-runs/other")

    assert %{"error" => %{"details" => %{"field" => "credentials_ref"}}} =
             c.conn
             |> post(api(c, "/data-sources/#{id}/credential"), %{
               "credentials_ref" => "secret://l11-runs/other"
             })
             |> json_response(422)

    assert {:ok, %{credentials_ref: "secret://l11-runs/other"}} =
             DataSources.fetch_data_source(other["id"])
  end

  test "a failed run's error is {code, message}; Retry answers the run (C, D)", c do
    source = register_byo!(c, "Mission QuestDB", "secret://l11-runs/run")

    assert %{"data" => %{"run" => %{"job_id" => job_id, "status" => "queued"}}} =
             c.conn
             |> post(api(c, "/data-sources/#{source["id"]}/tsdb/provision"))
             |> json_response(202)

    assert [%{job_id: ^job_id} = claimed] = Jobs.claim_jobs(1)

    {:ok, _failed} =
      Jobs.record_execution_result(
        claimed,
        {:error, :tsdb_backend_lifecycle_executor_not_configured}
      )

    assert %{"data" => %{"runs" => [run]}} =
             c.conn |> get(api(c, "/data-sources/#{source["id"]}")) |> json_response(200)

    assert %{
             "status" => "failed",
             "actions" => ["retry"],
             "error" => %{
               "code" => "tsdb_executor_not_configured",
               "message" => "This environment has nothing configured" <> _
             }
           } = run

    assert %{"data" => %{"run" => %{"job_id" => ^job_id, "status" => "queued", "error" => nil}}} =
             c.conn
             |> post(api(c, "/data-source-runs/#{job_id}/retry"))
             |> json_response(202)
  end

  defp api(c, path), do: "/api/console/v1/missions/#{c.mission.mission_id}" <> path

  defp register_byo!(c, name, credentials_ref) do
    c.conn
    |> post(api(c, "/data-sources"), %{
      "display_name" => name,
      "logical_source" => "telemetry",
      "kind" => "byo_tsdb",
      "isolation_level" => "mission_isolated",
      "storage" => "questdb",
      "credentials_ref" => credentials_ref
    })
    |> json_response(201)
    |> get_in(["data", "source"])
  end
end
