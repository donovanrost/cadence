defmodule Cadence.Contacts.JobOutcomeUnknownAttentionTest do
  @moduledoc "The job_outcome_unknown attention source (ux U54; director and lead 11-14)."
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Contacts.{JobOutcomeUnknownAttention, JobOutcomeWords}
  alias Cadence.Jobs
  alias Cadence.Jobs.BackgroundJobRow

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))
    org = "org-ou-" <> id
    mission = "mission-ou-" <> id
    persist_mission_scope(org, mission)
    %{org: org, mission: mission, scope: TelemetryDecomFixtures.user_scope(org, "op")}
  end

  test "a job Cadence stopped during is one open item per run; a relabelled one isn't", c do
    job = cut_off!(c.mission, :tsdb_backend_lifecycle, %{"operation" => "provision"})

    # The rows relabelled after the 11-14 fix carry no cause: no item, no Retry (director).
    relabelled = cut_off!(c.mission, :catalog_import_run, %{})

    Repo.update_all(from(r in BackgroundJobRow, where: r.job_id == ^relabelled.job_id),
      set: [failure_reason: %{"value" => %{"reason" => "outcome_unknown", "previous" => %{}}}]
    )

    assert [item] = JobOutcomeUnknownAttention.items(c.org, c.mission)
    assert item.id == "job_outcome_unknown:#{job.job_id}:1"
    assert %{state: "open", actions: ["retry", "close"], resolution: nil} = item
    assert %{type_key: "tsdb_backend_lifecycle", attempt: 1} = item.job

    assert item.words == %{
             noun: "Provisioning a source",
             check_place: "in the source's database",
             consequence: "provision it twice"
           }

    assert %DateTime{} = item.started_at
    assert %DateTime{} = item.found_at
    assert %{open: 1, acknowledged: 0} = JobOutcomeUnknownAttention.counts(c.org, c.mission)
  end

  test "a job's carried facts name it", c do
    cut_off!(c.mission, :replay_telemetry_scope, %{
      "span_from" => "2026-11-13T02:00:00Z",
      "span_to" => "2026-11-13T04:00:00Z"
    })

    cut_off!(c.mission, :telemetry_limit_evaluation, %{
      "limit_run_id" => "r",
      "definition_count" => 3
    })

    nouns = c.org |> JobOutcomeUnknownAttention.items(c.mission) |> Enum.map(& &1.words.noun)
    assert "Replay 11-13 02:00Z–04:00Z" in nouns
    assert "Limit check of 3 definitions" in nouns
  end

  test "close needs a note and leaves the job as it is", c do
    job = cut_off!(c.mission, :contact_schedule_operation, %{})
    [item] = JobOutcomeUnknownAttention.items(c.org, c.mission)

    assert {:error, :reason_required} =
             JobOutcomeUnknownAttention.resolve(c.scope, c.mission, item.id, " ")

    assert {:ok,
            %{
              state: "resolved",
              resolution: %{
                action: "closed",
                actor: %{"kind" => "user", "id" => _, "name" => _},
                at: %DateTime{},
                note: "Booked.",
                provider_reference: nil
              }
            }} = JobOutcomeUnknownAttention.resolve(c.scope, c.mission, item.id, "Booked.")

    assert {:ok, %{status: :outcome_unknown}} = Cadence.fetch_background_job(job.job_id)
    assert [] = JobOutcomeUnknownAttention.items(c.org, c.mission)

    assert {:error, :attention_item_not_open} =
             JobOutcomeUnknownAttention.resolve(c.scope, c.mission, item.id, "Again.")

    assert [%{id: id, action: "closed", note: "Booked."}] =
             JobOutcomeUnknownAttention.resolved_since(
               c.org,
               c.mission,
               DateTime.add(DateTime.utc_now(), -60)
             )

    assert id == item.id
  end

  test "retry needs the confirmation; two at once: one wins and the job is queued once", c do
    job = cut_off!(c.mission, :contact_schedule_operation, %{})
    [item] = JobOutcomeUnknownAttention.items(c.org, c.mission)

    assert {:error, :confirmation_required} =
             JobOutcomeUnknownAttention.retry(c.scope, c.mission, item.id, false, nil)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn ->
          JobOutcomeUnknownAttention.retry(c.scope, c.mission, item.id, true, "Checked.")
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    assert [{:error, :attention_item_not_open}, {:ok, %{resolution: %{action: "retried"}}}] =
             Enum.sort_by(results, &elem(&1, 0))

    assert {:ok, %{status: :queued, attempt_count: 1}} = Cadence.fetch_background_job(job.job_id)
  end

  test "a retried job cut off again is a new item next to the resolved one", c do
    job = cut_off!(c.mission, :contact_schedule_operation, %{})
    [first] = JobOutcomeUnknownAttention.items(c.org, c.mission)
    {:ok, _} = JobOutcomeUnknownAttention.retry(c.scope, c.mission, first.id, true, nil)

    assert [_] = Jobs.claim_jobs(1)
    assert %{outcome_unknown: 1} = Jobs.recover_running_jobs(fn _type -> false end)

    assert [second] = JobOutcomeUnknownAttention.items(c.org, c.mission)
    assert second.id == "job_outcome_unknown:#{job.job_id}:2"
    refute second.id == first.id
  end

  test "words never carry a blank name" do
    assert %{noun: "Booking at the provider", check_place: "with the provider"} =
             JobOutcomeWords.words(:contact_schedule_operation, %{
               action: "reserve",
               provider_name: " "
             })

    assert %{noun: "Cancel at Northlight", consequence: "send a second cancel"} =
             JobOutcomeWords.words(:contact_schedule_operation, %{
               action: "cancel",
               provider_name: "Northlight"
             })

    assert %{noun: "Catalog import"} = JobOutcomeWords.words(:catalog_import_run, %{})

    # Names from the facts the job carried (ux U54); older jobs keep the bare noun.
    assert %{noun: "Battery margin evaluation"} =
             JobOutcomeWords.words(:derived_telemetry_evaluation, %{
               definition_name: "Battery margin"
             })

    assert %{noun: "Derived telemetry evaluation of 3 definitions"} =
             JobOutcomeWords.words(:derived_telemetry_evaluation, %{definition_count: 3})

    assert %{noun: "Derived telemetry evaluation"} =
             JobOutcomeWords.words(:derived_telemetry_evaluation, %{})

    assert %{noun: "EPS.batt_voltage limit check"} =
             JobOutcomeWords.words(:telemetry_limit_evaluation, %{
               definition_name: "EPS.batt_voltage"
             })

    assert %{noun: "Limit check of 3 definitions"} =
             JobOutcomeWords.words(:telemetry_limit_evaluation, %{definition_count: 3})

    assert %{noun: "Replay 11-13 23:00Z–11-14 01:00Z"} =
             JobOutcomeWords.words(:replay_telemetry_scope, %{
               span_from: "2026-11-13T23:00:00Z",
               span_to: "2026-11-14T01:00:00Z"
             })

    # #702 retired historical workflows: a leftover job of that type reads as any Cadence job.
    assert %{noun: "A Cadence job"} =
             JobOutcomeWords.words(:telemetry_historical_data_workflow, %{})

    assert %{
             noun: "A Cadence job",
             check_place: "where it acts",
             consequence: "repeat what it did"
           } =
             JobOutcomeWords.words(:something_new, %{})
  end

  # A job claimed, then found :running at a node start and not safe to run again.
  defp cut_off!(mission, job_type, payload) do
    {:ok, job} = Jobs.enqueue(job_type, mission, "run-" <> Ecto.UUID.generate(), payload)
    assert [_ | _] = Jobs.claim_jobs(5)
    Jobs.recover_running_jobs(fn _type -> false end)
    job
  end
end
