defmodule Cadence.Reads.ActionQueue do
  @moduledoc """
  The operator's ranked action queue for a mission (console Now, A2).

  Ranking follows ux ruling U11:

    * **P1, act now:** critical alarms (active alarm episodes, both sources) and critical flight
      events (a catalog state alarm such as `MODE = SAFE`); failed or indeterminate commands
      (verify failed, release uncertain) within the failure lookback window.
    * **P2, needs you soon:** caution alarms and flight events; approval-pending command
      requests waiting on the viewer (not requested by them); stale spacecraft,
      grouped by plane.
    * **P3, when you can:** setup gaps (readiness `blocker` / `not_set_up`
      findings), ground limits not configured, spacecraft never heard from, a change set
      staged for more than 24 h (`ActionQueue.ChangeSetItems`).

  Identical causes are grouped into one item: alarms by `{source, severity,
  point, condition}` on each spacecraft's worst active episode (see
  `ActionQueue.AlarmItems`), stale
  spacecraft by plane, failed commands by `{command, outcome}`. Within a
  priority, alarm items whose episodes are all acknowledged go last; then items
  sort by `due_at` (time to consequence, soonest first), then `since` (oldest
  first), then a flight event before any other kind (a mode change usually explains the alarms
  after it). `due_at` is always `nil` until contact and
  propagation data exist (M7, D1).

  Missed passes and stations with issues come from `ActionQueue.ContactItems`, and
  needs-acknowledgment items from `ActionQueue.AttentionItems`. Not derived: no-ACK retries,
  because there's no automatic retry (DECISIONS #69).
  """

  alias Cadence.Auth.Scope
  alias Cadence.Reads.ActionQueue.{AlarmItems, AttentionItems, ChangeSetItems, ContactItems, Item}

  alias Cadence.Reads.{
    AlarmEpisodes,
    CommandGroups,
    Commands,
    FleetStatus,
    Readiness
  }

  @default_failure_lookback_s 86_400
  @episode_limit 200
  @failed_statuses [:failed, :indeterminate]
  @setup_severities [:blocker, :not_set_up]

  @type priority :: 1 | 2 | 3
  @type kind ::
          :alarm
          | :flight_event
          | :command_failed
          | :approval
          | :stale
          | :setup
          | :limits_not_configured
          | :never_heard
          | :attention
          | :missed_pass
          | :station
          | :change_set_stale

  @doc "Loads every input and builds the queue for the scope's user."
  @spec load(Scope.t(), binary(), keyword()) :: map()
  def load(%Scope{organization_id: organization_id} = scope, mission_id, opts \\ []) do
    viewer_user_id = scope.user && scope.user.user_id
    {episodes, truncated?} = episodes(scope, mission_id)
    requests = Cadence.Commanding.list_command_requests(organization_id, mission_id)

    commands =
      Commands.snapshot(organization_id, mission_id,
        requests: fn _org, _mission, _opts -> requests end
      )

    fleet = FleetStatus.load(organization_id, mission_id, opts)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    lookback_s = Keyword.get_lazy(opts, :failure_lookback_s, &failure_lookback_s/0)

    build(%{
      fleet: fleet,
      attention: AttentionItems.load(scope, mission_id, fleet, now),
      contact_items: ContactItems.load(scope, mission_id, fleet, now, lookback_s),
      change_set_items: ChangeSetItems.load(organization_id, mission_id, now),
      episodes: episodes,
      alarms_truncated: truncated?,
      command_rows: commands.rows,
      target_spacecraft:
        Cadence.SourceEndpoints.spacecraft_for_source_endpoints(
          organization_id,
          mission_id,
          Enum.map(commands.rows, & &1.target)
        ),
      groups_awaiting:
        CommandGroups.list(organization_id, mission_id, viewer_user_id, awaiting_me: true),
      viewer_user_id: viewer_user_id,
      limits_configured?: Cadence.Limits.list_limit_definitions(mission_id) != [],
      findings: Readiness.evaluate(organization_id, mission_id).findings,
      now: now,
      failure_lookback_s: lookback_s
    })
  end

  defp episodes(scope, mission_id) do
    case AlarmEpisodes.list(scope, mission_id, %{state: "active", limit: @episode_limit}) do
      {:ok, %{episodes: episodes, summary: summary}} ->
        {episodes, summary.active > length(episodes)}

      {:error, _reason} ->
        {[], false}
    end
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
        AlarmItems.items(Map.get(input, :episodes, []), by_id),
        failed_items(Map.get(input, :command_rows, []), now, input.failure_lookback_s, targets),
        approval_items(input, targets),
        stale_items(fleet.spacecraft),
        setup_items(input),
        never_heard_items(fleet.spacecraft),
        attention_input(input).items,
        Map.get(input, :contact_items, []),
        Map.get(input, :change_set_items, [])
      ]
      |> List.flatten()
      |> Enum.sort_by(&sort_key/1)

    %{
      observed_at: now,
      stale_after_s: fleet.stale_after_s,
      failure_lookback_s: input.failure_lookback_s,
      alarms_truncated: Map.get(input, :alarms_truncated, false),
      counts: counts(items),
      items: items,
      resolved: attention_input(input).resolved,
      missed_pass_horizon_s: ContactItems.missed_pass_horizon_s()
    }
  end

  defp attention_input(input), do: Map.get(input, :attention) || %{items: [], resolved: []}

  # -- commands ----------------------------------------------------------------

  defp failed_items(rows, now, lookback_s, targets) do
    cutoff = DateTime.add(now, -lookback_s)

    rows
    |> Enum.filter(&recent_failure?(&1, cutoff))
    |> Enum.group_by(&{&1.command_id, &1.status})
    |> Enum.map(fn {{command_id, status}, group} ->
      group = Enum.sort_by(group, & &1.occurred_at, DateTime)

      Item.new(%{
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

  # A decision waiting on the viewer: command groups awaiting their GO (one each, however many
  # members). Every request is a group's member, so there is no request-level decision.
  defp approval_items(%{groups_awaiting: [_ | _] = groups}, _targets) do
    Item.new(%{
      id: "approval:viewer",
      priority: 2,
      kind: :approval,
      state: :caution,
      since: Item.min_datetime(Enum.map(groups, & &1.requested_at)),
      count: length(groups),
      command_groups:
        Enum.map(
          groups,
          &Map.take(&1, [
            :id,
            :title,
            :member_count,
            :target_count,
            :requested_by,
            :requested_at
          ])
        )
    })
  end

  defp approval_items(_input, _targets), do: []

  defp target_spacecraft_id(row, targets), do: Map.get(targets.endpoints, row.target)

  defp target_members(rows, targets) do
    rows
    |> Enum.map(&target_spacecraft_id(&1, targets))
    |> Enum.uniq()
    |> Enum.flat_map(fn id ->
      case Map.fetch(targets.by_id, id) do
        {:ok, craft} -> [Item.member(craft)]
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
      Item.new(%{
        id: "stale:plane:#{plane || "none"}",
        priority: 2,
        kind: :stale,
        state: :stale,
        since: group |> Enum.map(& &1.last_received_at) |> Item.min_datetime(),
        count: length(group),
        plane: plane,
        spacecraft: Enum.map(group, &Item.member/1)
      })
    end)
  end

  defp never_heard_items(spacecraft) do
    case Enum.filter(spacecraft, &(&1.state == :never_heard)) do
      [] ->
        []

      group ->
        Item.new(%{
          id: "never_heard",
          priority: 3,
          kind: :never_heard,
          state: :off,
          count: length(group),
          spacecraft: Enum.map(group, &Item.member/1)
        })
    end
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
          Item.new(%{
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
        Item.new(%{
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

  # Within a priority, items whose alarms are all acknowledged go after the rest.
  defp sort_key(item) do
    {item.priority, if(acknowledged_only?(item), do: 1, else: 0), unix(item.due_at),
     unix(item.since), if(item.kind == :flight_event, do: 0, else: 1), item.id}
  end

  defp acknowledged_only?(%{kind: kind, acknowledged: n, count: n})
       when kind in [:alarm, :flight_event],
       do: true

  defp acknowledged_only?(%{kind: :attention, attention: %{state: "acknowledged"}}), do: true
  defp acknowledged_only?(_item), do: false

  # nil sorts after every time.
  defp unix(nil), do: :infinity
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)
end
