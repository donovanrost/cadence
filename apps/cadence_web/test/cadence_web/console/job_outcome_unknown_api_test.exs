defmodule CadenceWeb.Console.JobOutcomeUnknownAPITest do
  @moduledoc "U54 over HTTP: retry needs the confirmation (202 with the run), close needs a note."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Jobs
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission.mission_id,
      base: "/api/console/v1/missions/#{mission.mission_id}/attention/job_outcome_unknown/"
    }
  end

  test "retry: 422 without the confirmation, then 202 with the queued run", c do
    job = cut_off!(c.mission)
    id = "job_outcome_unknown:#{job.job_id}:1"

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"confirmed" => _}}} =
             c.conn |> post(c.base <> id <> "/retry", %{}) |> json_response(422)

    assert %{
             "data" => %{
               "item" => %{"state" => "resolved", "resolution" => %{"action" => "retried"}},
               "run" => %{"job_id" => job_id, "status" => "queued"}
             }
           } =
             c.conn
             |> post(c.base <> id <> "/retry", %{"confirmed" => true, "note" => "Checked."})
             |> json_response(202)

    assert job_id == job.job_id

    assert %{"error" => %{"code" => "attention_item_not_open"}} =
             c.conn
             |> post(c.base <> id <> "/retry", %{"confirmed" => true})
             |> json_response(409)
  end

  test "close: 422 without a note, then resolved with it", c do
    job = cut_off!(c.mission)
    id = "job_outcome_unknown:#{job.job_id}:1"

    assert %{"error" => %{"details" => %{"action_text" => _}}} =
             c.conn |> post(c.base <> id <> "/resolve", %{}) |> json_response(422)

    assert %{
             "data" => %{
               "source" => "job_outcome_unknown",
               "state" => "resolved",
               "resolution" => %{
                 "action" => "closed",
                 "note" => "It booked.",
                 "actor" => %{"kind" => "user", "name" => "Mira K."},
                 "provider_reference" => nil
               },
               "acknowledged_by" => nil,
               "provider_message" => nil
             }
           } =
             c.conn
             |> post(c.base <> id <> "/resolve", %{"action_text" => "It booked."})
             |> json_response(200)
  end

  defp cut_off!(mission) do
    {:ok, job} =
      Jobs.enqueue(:contact_schedule_operation, mission, "run-" <> Ecto.UUID.generate(), %{})

    [_ | _] = Jobs.claim_jobs(5)
    Jobs.recover_running_jobs(fn _type -> false end)
    job
  end
end
