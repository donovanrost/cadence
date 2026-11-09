defmodule Cadence.Reads.ActionQueueTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Reads.ActionQueue

  @now ~U[2026-11-08 02:41:17Z]

  defp craft(id, state, opts \\ []) do
    %{
      id: id,
      name: String.upcase(id),
      scid: Keyword.get(opts, :scid),
      plane: Keyword.get(opts, :plane),
      state: state,
      stale: Keyword.get(opts, :stale, state == :stale),
      last_received_at: Keyword.get(opts, :last_received_at, ago(60)),
      violating_points: Keyword.get(opts, :violating_points, 0)
    }
  end

  defp alarm(spacecraft_id, severity, opts) do
    %{
      spacecraft_id: spacecraft_id,
      active?: true,
      severity: severity,
      point_id: Keyword.get(opts, :point_id, "EPS.VBAT"),
      point_name: Keyword.get(opts, :point_name, "VBAT"),
      subsystem: "EPS",
      limit_state: Keyword.get(opts, :condition, :red_low),
      evaluated_value: Keyword.get(opts, :value, 23.1),
      first_crossed_at: Keyword.get(opts, :first_crossed_at),
      generation_time: nil,
      receipt_time: Keyword.get(opts, :received_at, ago(5))
    }
  end

  defp command_row(id, status, opts \\ []) do
    %{
      command_request_id: id,
      command_id: Keyword.get(opts, :command_id, "PWR_MODE"),
      command_name: "Set power mode",
      target: "ep-1",
      target_name: "EARENDIL-001",
      requested_by: "Mira K.",
      requested_at: Keyword.get(opts, :requested_at, ago(600)),
      status: status,
      occurred_at: Keyword.get(opts, :occurred_at, ago(300))
    }
  end

  defp request(id, state, requester) do
    %CommandRequest{
      command_request_id: id,
      mission_id: "m1",
      lifecycle_state: state,
      requested_by: %{"id" => requester}
    }
  end

  defp ago(seconds), do: DateTime.add(@now, -seconds)

  defp build(input) do
    ActionQueue.build(
      Map.merge(
        %{
          fleet: %{stale_after_s: 900, spacecraft: Map.get(input, :spacecraft, [])},
          now: @now,
          failure_lookback_s: 86_400,
          limits_configured?: true,
          viewer_user_id: "viewer"
        },
        input
      )
    )
  end

  defp ids(result), do: Enum.map(result.items, & &1.id)

  describe "build/1 limit alarms" do
    test "groups each spacecraft's worst alarm by point and condition, critical first" do
      result =
        build(%{
          spacecraft: [
            craft("a", :critical, plane: 1),
            craft("b", :critical, plane: 1),
            craft("c", :caution, plane: 2)
          ],
          alarms: [
            alarm("a", :critical, first_crossed_at: ago(100)),
            alarm("a", :caution, point_id: "THM.T1", condition: :yellow_high),
            alarm("b", :critical, first_crossed_at: ago(400), value: 22.8),
            alarm("c", :caution, point_id: "THM.T1", condition: :yellow_high)
          ]
        })

      assert ids(result) == [
               "alarm:critical:EPS.VBAT:red_low",
               "alarm:caution:THM.T1:yellow_high"
             ]

      [critical, caution] = result.items
      assert critical.priority == 1
      assert critical.count == 2
      assert critical.since == ago(400)
      assert Enum.map(critical.spacecraft, & &1.id) == ["b", "a"]
      assert hd(critical.spacecraft).value == 22.8
      assert critical.point == %{id: "EPS.VBAT", name: "VBAT", subsystem: "EPS"}
      assert critical.condition == "red_low"

      assert caution.priority == 2
      assert Enum.map(caution.spacecraft, & &1.id) == ["c"]
      assert result.counts == %{p1: 1, p2: 1, p3: 0, spacecraft_p1: 2}
    end

    test "ignores nominal and inactive rows and unknown spacecraft" do
      result =
        build(%{
          spacecraft: [craft("a", :nominal)],
          alarms: [
            alarm("a", :nominal, []),
            %{alarm("a", :critical, []) | active?: false},
            alarm("ghost", :critical, [])
          ]
        })

      assert result.items == []
    end
  end

  describe "build/1 commands" do
    test "failed and indeterminate commands in the lookback are P1, grouped by command" do
      result =
        build(%{
          spacecraft: [craft("sc1", :nominal)],
          target_spacecraft: %{"ep-1" => "sc1"},
          command_rows: [
            command_row("r1", :failed, occurred_at: ago(60)),
            command_row("r2", :failed, occurred_at: ago(120)),
            command_row("r3", :indeterminate),
            command_row("r4", :failed, occurred_at: ago(90_000)),
            command_row("r5", :released)
          ]
        })

      # Oldest first within P1: the indeterminate request (5 min ago) predates both failures.
      assert ids(result) == [
               "command_failed:indeterminate:PWR_MODE",
               "command_failed:failed:PWR_MODE"
             ]

      [_uncertain, failed] = result.items
      assert failed.outcome == :failed
      assert failed.since == ago(120)
      assert Enum.map(failed.command_requests, & &1.id) == ["r2", "r1"]
      assert failed.command == %{id: "PWR_MODE", name: "Set power mode"}
      assert [%{id: "sc1"}] = failed.spacecraft
      assert hd(failed.command_requests).spacecraft_id == "sc1"
      assert result.counts.spacecraft_p1 == 1
    end

    test "approval-pending requests count only when another operator requested them" do
      result =
        build(%{
          requests: [
            request("mine", :approval_pending, "viewer"),
            request("theirs", :approval_pending, "other"),
            request("queued", :queued, "other")
          ],
          command_rows: [
            command_row("mine", :approval_pending),
            command_row("theirs", :approval_pending),
            command_row("queued", :queued)
          ]
        })

      assert [%{id: "approval:viewer", priority: 2, count: 1} = item] = result.items

      assert [%{id: "theirs", target: %{id: "ep-1", name: "EARENDIL-001"}}] =
               item.command_requests
    end
  end

  describe "build/1 freshness and setup" do
    test "stale spacecraft group by plane; never heard and setup gaps are P3" do
      result =
        build(%{
          spacecraft: [
            craft("s1", :stale, plane: 2, last_received_at: ago(4_000)),
            craft("s2", :stale, plane: 2, last_received_at: ago(2_000)),
            craft("s3", :stale),
            craft("n1", :never_heard, last_received_at: nil)
          ],
          limits_configured?: false,
          findings: [
            %{
              id: "stations.no_ground_stations",
              area: :stations,
              severity: :not_set_up,
              cause: :no_ground_stations,
              affected_count: 0
            },
            %{
              id: "apps.app_not_installed:dashboards",
              area: :apps,
              severity: :optional,
              cause: :"app_not_installed:dashboards",
              affected_count: 0
            }
          ]
        })

      assert ids(result) == [
               "stale:plane:2",
               "stale:plane:none",
               "limits_not_configured",
               "never_heard",
               "setup:stations.no_ground_stations"
             ]

      [plane2 | _rest] = result.items
      assert plane2.plane == 2
      assert plane2.since == ago(4_000)
      assert plane2.count == 2
      assert result.counts.p3 == 3
    end

    test "a missing limits app replaces the limits-not-configured item" do
      result =
        build(%{
          limits_configured?: false,
          findings: [
            %{
              id: "apps.app_not_installed:limits",
              area: :apps,
              severity: :not_set_up,
              cause: :"app_not_installed:limits",
              affected_count: 0
            }
          ]
        })

      assert ids(result) == ["setup:apps.app_not_installed:limits"]
    end

    test "an empty mission has an empty queue" do
      assert %{items: [], counts: %{p1: 0, p2: 0, p3: 0}} = build(%{})
    end
  end
end
