defmodule Cadence.Reads.ActionQueue do
  @moduledoc """
  The operator's ranked action queue for a mission (console Now, A2).

  Ranking follows ux ruling U11:

    * **P1, act now:** critical limit alarms; failed or indeterminate commands
      (verify failed, release uncertain) within the failure lookback window.
    * **P2, needs you soon:** caution limit alarms; approval-pending command
      requests waiting on the viewer (not requested by them); stale spacecraft,
      grouped by plane.
    * **P3, when you can:** setup gaps (readiness `blocker` / `not_set_up`
      findings), ground limits not configured, spacecraft never heard from.

  Identical causes are grouped into one item: limit alarms by
  `{severity, point, condition}` on each spacecraft's worst active alarm, stale
  spacecraft by plane, failed commands by `{command, outcome}`. Within a
  priority, items sort by `due_at` (time to consequence, soonest first), then
  `since` (oldest first). `due_at` is always `nil` until contact and
  propagation data exist (M7, D1).

  Not derived yet: critical flight events (safe mode), missed passes, degraded
  stations and no-ACK retries, because there is no source for them.
  """

  alias Cadence.Reads.{AlarmList, CommandCounts, Commands, FleetStatus, Readiness}

  @default_failure_lookback_s 86_400
  @limit_rank %{critical: 2, caution: 1}
  @failed_statuses [:failed, :indeterminate]
  @setup_severities [:blocker, :not_set_up]

  @type priority :: 1 | 2 | 3
  @type kind ::
          :alarm
          | :command_failed
          | :approval
          | :stale
          | :setup
          | :limits_not_configured
          | :never_heard

  @doc "Loads every input and builds the queue for `viewer_user_id`."
  @spec load(binary(), binary(), binary() | nil, keyword()) :: map()
  def load(organization_id, mission_id, viewer_user_id, opts \\ []) do
    requests = Cadence.Commanding.list_command_requests(organization_id, mission_id)

    commands =
      Commands.snapshot(organization_id, mission_id,
        requests: fn _org, _mission, _opts -> requests end
      )

    build(%{
      fleet: FleetStatus.load(organization_id, mission_id, opts),
      alarms: AlarmList.load(organization_id, mission_id, %{state: "active"}).alarms,
      command_rows: commands.rows,
      target_spacecraft:
        Cadence.SourceEndpoints.spacecraft_for_source_endpoints(
          organization_id,
          mission_id,
          Enum.map(commands.rows, & &1.target)
        ),
      requests: requests,
      viewer_user_id: viewer_user_id,
      limits_configured?: Cadence.Limits.list_limit_definitions(mission_id) != [],
      findings: Readiness.evaluate(organization_id, mission_id).findings,
      now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0),
      failure_lookback_s: Keyword.get_lazy(opts, :failure_lookback_s, &failure_lookback_s/0)
    })
  end

  @doc "Lookback for failed commands, in seconds (`config :cadence, :action_queue_failure_lookback_s`)."
  @spec failure_lookback_s() :: pos_integer()
  def failure_lookback_s,
    do:
      Application.get_env(:cadence, :action_queue_failure_lookback_s, @default_failure_lookback_s)

  @doc "Pure builder; see `load/4` for the inputs."
  @spec build(map()) :: map()
  def build(%{fleet: fleet, now: now} = input) do
    by_id = Map.new(fleet.spacecraft, &{&1.id, &1})
    targets = %{by_id: by_id, endpoints: Map.get(input, :target_spacecraft, %{})}

    items =
      [
        alarm_items(Map.get(input, :alarms, []), by_id),
        failed_items(Map.get(input, :command_rows, []), now, input.failure_lookback_s, targets),
        approval_items(input, targets),
        stale_items(fleet.spacecraft),
        setup_items(input),
        never_heard_items(fleet.spacecraft)
      ]
      |> List.flatten()
      |> Enum.sort_by(&sort_key/1)

    %{
      observed_at: now,
      stale_after_s: fleet.stale_after_s,
      failure_lookback_s: input.failure_lookback_s,
      counts: counts(items),
      items: items
    }
  end

  # -- limit alarms ------------------------------------------------------------

  defp alarm_items(alarms, by_id) do
    alarms
    |> Enum.filter(&queued_alarm?(&1, by_id))
    |> Enum.group_by(& &1.spacecraft_id)
    |> Enum.map(fn {_id, rows} -> Enum.max_by(rows, &alarm_rank/1) end)
    |> Enum.group_by(&{&1.severity, &1.point_id, condition(&1)})
    |> Enum.map(fn {{severity, point_id, condition}, worst} ->
      members =
        worst
        |> Enum.sort_by(&(alarm_since(&1) || &1.receipt_time), &earlier?/2)
        |> Enum.map(&alarm_member(&1, Map.fetch!(by_id, &1.spacecraft_id)))

      first = hd(worst)

      item(%{
        id: "alarm:#{severity}:#{point_id}:#{condition}",
        priority: if(severity == :critical, do: 1, else: 2),
        kind: :alarm,
        state: severity,
        since: worst |> Enum.map(&alarm_since/1) |> min_datetime(),
        count: length(members),
        spacecraft: members,
        point: %{
          id: point_id,
          name: first.point_name,
          subsystem: first.subsystem,
          unit: Map.get(first, :unit)
        },
        condition: condition
      })
    end)
  end

  defp queued_alarm?(row, by_id) do
    row.active? and row.severity in [:critical, :caution] and
      Map.has_key?(by_id, row.spacecraft_id)
  end

  defp alarm_rank(row) do
    {Map.fetch!(@limit_rank, row.severity),
     row.receipt_time && DateTime.to_unix(row.receipt_time, :microsecond)}
  end

  defp alarm_since(row), do: row.first_crossed_at || row.generation_time || row.receipt_time

  defp condition(row), do: row.limit_state && to_string(row.limit_state)

  defp alarm_member(row, craft) do
    craft
    |> member()
    |> Map.merge(%{value: row.evaluated_value, first_crossed_at: row.first_crossed_at})
  end

  # -- commands ----------------------------------------------------------------

  defp failed_items(rows, now, lookback_s, targets) do
    cutoff = DateTime.add(now, -lookback_s)

    rows
    |> Enum.filter(&recent_failure?(&1, cutoff))
    |> Enum.group_by(&{&1.command_id, &1.status})
    |> Enum.map(fn {{command_id, status}, group} ->
      group = Enum.sort_by(group, & &1.occurred_at, DateTime)

      item(%{
        id: "command_failed:#{status}:#{command_id}",
        priority: 1,
        kind: :command_failed,
        state: :critical,
        since: hd(group).occurred_at,
        count: length(group),
        spacecraft: target_members(group, targets),
        command: %{id: command_id, name: hd(group).command_name},
        outcome: status,
        command_requests: Enum.map(group, &request_ref(&1, targets))
      })
    end)
  end

  defp recent_failure?(row, cutoff) do
    row.status in @failed_statuses and not is_nil(row.occurred_at) and
      DateTime.compare(row.occurred_at, cutoff) != :lt
  end

  defp approval_items(%{command_rows: rows, requests: requests, viewer_user_id: viewer}, targets) do
    others =
      requests
      |> Enum.filter(&(&1.lifecycle_state == :approval_pending))
      |> Enum.reject(&(CommandCounts.requester_id(&1) == viewer))
      |> MapSet.new(& &1.command_request_id)

    case rows
         |> Enum.filter(&MapSet.member?(others, &1.command_request_id))
         |> Enum.sort_by(&(&1.requested_at || &1.occurred_at), &earlier?/2) do
      [] ->
        []

      waiting ->
        item(%{
          id: "approval:viewer",
          priority: 2,
          kind: :approval,
          state: :caution,
          since: waiting |> Enum.map(& &1.requested_at) |> min_datetime(),
          count: length(waiting),
          spacecraft: target_members(waiting, targets),
          command_requests: Enum.map(waiting, &request_ref(&1, targets))
        })
    end
  end

  defp approval_items(_input, _targets), do: []

  defp target_spacecraft_id(row, targets), do: Map.get(targets.endpoints, row.target)

  defp target_members(rows, targets) do
    rows
    |> Enum.map(&target_spacecraft_id(&1, targets))
    |> Enum.uniq()
    |> Enum.flat_map(fn id ->
      case Map.fetch(targets.by_id, id) do
        {:ok, craft} -> [member(craft)]
        :error -> []
      end
    end)
  end

  defp request_ref(row, targets) do
    %{
      id: row.command_request_id,
      command_name: row.command_name,
      target: %{id: row.target, name: row.target_name},
      spacecraft_id: target_spacecraft_id(row, targets),
      requested_by: row.requested_by,
      requested_at: row.requested_at,
      status: row.status,
      occurred_at: row.occurred_at
    }
  end

  # -- freshness ---------------------------------------------------------------

  defp stale_items(spacecraft) do
    spacecraft
    |> Enum.filter(&(&1.state == :stale))
    |> Enum.group_by(& &1.plane)
    |> Enum.map(fn {plane, group} ->
      item(%{
        id: "stale:plane:#{plane || "none"}",
        priority: 2,
        kind: :stale,
        state: :stale,
        since: group |> Enum.map(& &1.last_received_at) |> min_datetime(),
        count: length(group),
        plane: plane,
        spacecraft: Enum.map(group, &member/1)
      })
    end)
  end

  defp never_heard_items(spacecraft) do
    case Enum.filter(spacecraft, &(&1.state == :never_heard)) do
      [] ->
        []

      group ->
        item(%{
          id: "never_heard",
          priority: 3,
          kind: :never_heard,
          state: :off,
          count: length(group),
          spacecraft: Enum.map(group, &member/1)
        })
    end
  end

  defp member(craft) do
    %{
      id: craft.id,
      name: craft.name,
      scid: craft.scid,
      plane: craft.plane,
      stale: craft.stale,
      last_received_at: craft.last_received_at,
      violating_points: craft.violating_points,
      value: nil,
      first_crossed_at: nil
    }
  end

  # -- setup -------------------------------------------------------------------

  defp setup_items(input) do
    findings =
      input
      |> Map.get(:findings, [])
      |> Enum.filter(&(&1.severity in @setup_severities))

    limits_app_missing? = Enum.any?(findings, &(&1.cause == :"app_not_installed:limits"))

    limits =
      if Map.get(input, :limits_configured?, true) or limits_app_missing? do
        []
      else
        [
          item(%{
            id: "limits_not_configured",
            priority: 3,
            kind: :limits_not_configured,
            state: :off,
            count: 0
          })
        ]
      end

    limits ++
      Enum.map(findings, fn finding ->
        item(%{
          id: "setup:#{finding.id}",
          priority: 3,
          kind: :setup,
          state: :off,
          count: finding.affected_count,
          finding: finding
        })
      end)
  end

  # -- shared ------------------------------------------------------------------

  defp item(fields) do
    Map.merge(
      %{
        since: nil,
        due_at: nil,
        spacecraft: [],
        point: nil,
        condition: nil,
        plane: nil,
        command: nil,
        outcome: nil,
        command_requests: [],
        finding: nil
      },
      fields
    )
  end

  defp counts(items) do
    frequencies = Enum.frequencies_by(items, & &1.priority)

    %{
      p1: Map.get(frequencies, 1, 0),
      p2: Map.get(frequencies, 2, 0),
      p3: Map.get(frequencies, 3, 0),
      spacecraft_p1:
        items
        |> Enum.filter(&(&1.priority == 1))
        |> Enum.flat_map(& &1.spacecraft)
        |> Enum.uniq_by(& &1.id)
        |> length()
    }
  end

  defp sort_key(item) do
    {item.priority, unix(item.due_at), unix(item.since), item.id}
  end

  # nil sorts after every time.
  defp unix(nil), do: :infinity
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)

  defp earlier?(nil, _b), do: false
  defp earlier?(_a, nil), do: true
  defp earlier?(a, b), do: DateTime.compare(a, b) != :gt

  defp min_datetime(datetimes) do
    case Enum.reject(datetimes, &is_nil/1) do
      [] -> nil
      present -> Enum.min(present, DateTime)
    end
  end
end
