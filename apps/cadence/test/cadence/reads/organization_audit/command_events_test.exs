defmodule Cadence.Reads.OrganizationAudit.CommandEventsTest do
  @moduledoc """
  Director 11-15 / ux U59: a command group is one audit entry per decision, never one per
  member; Cadence's own cancels fold per group and reason; bounded however large the group.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Commanding.Groups.{CommandGroupEventRow, CommandGroupRow}
  alias Cadence.Control.Commanding.{GroupAbort, GroupDecision, GroupSubmission}
  alias Cadence.Reads.OrganizationAudit.CommandEvents

  defp actions(org, mission, opts \\ %{}),
    do: org |> CommandEvents.list(mission, opts) |> Enum.sort_by(& &1.at, DateTime)

  test "a group reads as its decisions: submitted, GO excluding, aborted; no member rows" do
    c = setup!(3)

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{
        log_entry: "Reset counters"
      })

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    approver = operator!(c)

    {:ok, _} =
      GroupDecision.decide(approver, c.mission, group.command_group_id, %{
        kind: :go_excluding,
        excluded: [Enum.at(c.spacecraft, 1)],
        note: "sc-2 in safe mode",
        expected_review: GroupDecision.review_token(group)
      })

    {:ok, _} = GroupAbort.abort(c.scope, c.mission, group.command_group_id, "Wrong mode")

    events = actions(c.org, c.mission)
    label = "SET_COUNTER for 3 spacecraft"

    assert [submitted, go, aborted] = events
    assert String.starts_with?(submitted.action, "Submitted " <> label)
    assert go.action == "Gave GO on #{label}, excluding 1 spacecraft"
    assert go.reason == "sc-2 in safe mode"
    assert go.actor.id == approver.user.user_id
    assert aborted.action == "Aborted #{label}: 2 uplinks canceled, 0 already sent"
    assert aborted.reason == "Wrong mode"

    assert Enum.all?(
             events,
             &(&1.kind == "commanding" and
                 &1.target == %{kind: "command_group", id: group.command_group_id, label: label})
           )
  end

  test "a 1,000 × 16 group is at most 6 rows; Cadence's cancels fold per reason" do
    org = "org-audit-scale"
    mission = "mission-audit-scale"
    Cadence.DataCase.persist_mission_scope(org, mission)
    group_id = "command_group_scale"
    now = DateTime.utc_now()

    commands =
      for i <- 0..15, do: %{"command_id" => "cmd_#{i}", "name" => "CMD_#{i}", "position" => i}

    targets = for i <- 1..1_000, do: %{"spacecraft_id" => "sc_#{i}"}

    Repo.insert_all(CommandGroupRow, [
      %{
        command_group_id: group_id,
        organization_id: org,
        mission_id: mission,
        state: "queued",
        title: "Fleet mode change",
        requested_at: now,
        resolved_at: now,
        member_count: 16_000,
        commands_document: %{"value" => commands},
        targets_document: %{"value" => targets},
        inserted_at: now,
        updated_at: now
      }
    ])

    user = %{"actor_kind" => "user", "user_id" => "user-1"}

    Repo.insert_all(
      CommandGroupEventRow,
      for {kind, offset} <- [{"submitted", 0}, {"approved", 1}] do
        %{
          event_id: "event-#{kind}",
          command_group_id: group_id,
          mission_id: mission,
          kind: kind,
          actor_document: %{"value" => user},
          at: DateTime.add(now, offset),
          payload_document: %{"value" => %{"second_go_required" => true}}
        }
      end
    )

    members =
      for t <- 1..1_000, k <- 0..15 do
        reason = if t <= 10, do: "release_basis_changed", else: "expired"

        %{
          command_request_id: "req-#{t}-#{k}",
          organization_id: org,
          mission_id: mission,
          source_endpoint_ref: "ep_#{t}",
          mission_model_revision_id: "model-1",
          command_id: "cmd_#{k}",
          command_name: "CMD_#{k}",
          lifecycle_state: "canceled",
          requested_at: now,
          command_group_id: group_id,
          group_target_index: t - 1,
          group_position: k,
          metadata_document: %{
            "value" => %{
              "cancellation" => %{
                "reason" => reason,
                "actor" => %{"actor_kind" => "system", "id" => "cadence:expiry"},
                "at" => now |> DateTime.add(60) |> DateTime.to_iso8601()
              }
            }
          },
          inserted_at: now,
          updated_at: now
        }
      end

    members |> Enum.chunk_every(2_000) |> Enum.each(&Repo.insert_all(CommandRequestRow, &1))

    events = actions(org, mission)
    assert length(events) <= 6
    label = "CMD_0 and 15 more for 1000 spacecraft"

    assert Enum.map(events, & &1.action) |> Enum.sort() ==
             Enum.sort([
               "Submitted #{label} · needs a second GO",
               "Gave GO on #{label}",
               "Canceled 15840 uplinks of #{label}: they expired before release",
               "Canceled 160 uplinks of #{label}: what they were approved against changed"
             ])

    assert %{kind: "service", name: "Cadence"} =
             Enum.find(events, &String.starts_with?(&1.action, "Canceled")).actor

    # The window is applied in SQL: nothing before `from`.
    assert actions(org, mission, %{from: DateTime.add(now, 3_600)}) == []
  end
end
