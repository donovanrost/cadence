defmodule Cadence.Reads.VerifierSeries do
  @moduledoc """
  What Uplink U2 plots for a command group (M26): the telemetry point its verifier watches, each
  target's own samples of it over the request window, the commanded value or band, and who met it.

    * The plotted verifier is the first command in stack order whose verifier watches a telemetry
      point. Commands verified only by the uplink acknowledgement (`transport:` subjects) have no
      point: the series says `point: nil` ("not plottable").
    * Each target's samples are that spacecraft's own (#38), decimated to at most 300.
    * At most 100 targets by default (`:target_ids` picks them); `truncated` says when more exist.
    * The history store is bounded (3 s, as the fleet read): on timeout `telemetry` is `:degraded`
      and samples are empty.
  """

  alias Cadence.Commanding
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Commanding.RequestValidation
  alias Cadence.Ops.PointCatalog
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.{SpacecraftLive, Telemetry}
  alias Cadence.Reads.VerifierSeries.Points

  @max_targets 100
  @max_samples 300
  @history_timeout_ms 3_000

  @spec load(binary(), binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(org, mission, group_id, opts \\ []) do
    with {:ok, group} <- GroupStore.fetch(org, mission, group_id) do
      members = GroupStore.members(org, mission, group_id)
      member_ids = MapSet.new(members, & &1.command_request_id)

      verifiers =
        org
        |> Commanding.list_command_verifier_instances(mission)
        |> Enum.filter(&MapSet.member?(member_ids, &1.command_request_id))

      {:ok, build(org, mission, group, members, verifiers, opts)}
    end
  end

  defp build(org, mission, group, members, verifiers, opts) do
    by_request = Enum.group_by(verifiers, & &1.command_request_id)
    plans_for = cached_plans(org, mission, members, opts)

    points =
      members
      |> Points.list(plans_for)
      |> Enum.map(&Map.put(&1, :point, point(org, mission, &1.subject, opts)))

    case select_point(points, Keyword.get(opts, :point)) do
      # U2: one point (?point=, else the first), plotted for the targets whose own verifiers watch it.
      %{} = selected ->
        plotted_members = Enum.filter(members, &(&1.command_request_id in selected.request_ids))
        plotted = {selected.position, selected.point, selected.plan}

        org
        |> series(mission, group, plotted_members, by_request, plotted, opts)
        |> Map.put(:points, Enum.map(points, &point_entry(&1, members, group)))

      nil ->
        org
        |> by_instances(mission, group, members, verifiers, by_request, opts)
        |> Map.put(:points, [])
    end
  end

  # No plan names a telemetry point: the instances may (before U2's points), else not plottable.
  defp by_instances(org, mission, group, members, verifiers, by_request, opts) do
    case plotted(org, mission, members, by_request, opts) do
      nil ->
        not_plottable(org, mission, group, members, verifiers, opts)

      {position, subject, plan} ->
        plotted_members = Enum.filter(members, &(&1.group_slot.position == position))
        point = point(org, mission, subject, opts)
        series(org, mission, group, plotted_members, by_request, {position, point, plan}, opts)
    end
  end

  defp select_point([], _wanted), do: nil
  defp select_point([first | _], nil), do: first

  defp select_point([first | _] = points, wanted),
    do: Enum.find(points, first, &(&1.point.id == wanted))

  defp point_entry(entry, members, group) do
    index_of = Map.new(members, &{&1.command_request_id, &1.group_slot.target_index})
    spacecraft = Map.new(group.targets, &{&1["index"], &1["spacecraft_id"]})

    %{
      point_id: entry.point.id,
      name: entry.point.name,
      verifier_name: entry.verifier_name,
      position: entry.position,
      spacecraft_ids:
        entry.request_ids
        |> Enum.map(&Map.get(spacecraft, Map.get(index_of, &1)))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  # A member's own verifier plans, looked up once per (pinned revision, command).
  defp cached_plans(org, mission, members, opts) do
    key = &{&1.mission_model_revision_id, &1.command_id}

    by_key =
      members
      |> Enum.uniq_by(key)
      |> Map.new(&{key.(&1), plans(org, mission, &1, opts)})

    &Map.get(by_key, key.(&1), [])
  end

  # The first stack position whose command has a verifier on a telemetry point: from the command's
  # verifier plans (known before release), else from its verifier instances.
  defp plotted(org, mission, members, by_request, opts) do
    members
    |> Enum.group_by(& &1.group_slot.position)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {position, [member | _] = at_position} ->
      plan = org |> plans(mission, member, opts) |> Enum.find(&telemetry_point/1)

      instance =
        at_position
        |> Enum.flat_map(&Map.get(by_request, &1.command_request_id, []))
        |> Enum.find(&telemetry_point/1)

      case plan || instance do
        nil -> nil
        source -> {position, telemetry_point(source), plan}
      end
    end)
  end

  # `:plans_fun` (tests) replaces the catalog lookup: `(member -> [VerifierPlan])`.
  defp plans(org, mission, member, opts) do
    case Keyword.get(opts, :plans_fun) do
      nil -> catalog_plans(org, mission, member)
      fun -> fun.(member)
    end
  end

  defp catalog_plans(org, mission, member) do
    case RequestValidation.resolve_basis(
           org,
           mission,
           member.mission_model_revision_id,
           member.command_id,
           member.source_endpoint_ref
         ) do
      {:ok, %{verifier_plans: plans}} when is_list(plans) -> plans
      _not_active -> []
    end
  end

  defp telemetry_point(verifier), do: Points.subject(verifier)

  # Nothing to plot: the commands are verified only by the uplink acknowledgement, or not at all.
  defp not_plottable(org, mission, group, members, verifiers, opts) do
    first = members |> Enum.sort_by(& &1.group_slot.position) |> List.first()
    verified? = verifiers != [] or Enum.any?(members, &(plans(org, mission, &1, opts) != []))

    %{
      verifier: first && verifier_ref(first),
      point: nil,
      reason: if(verified?, do: "verified_by_uplink_acknowledgement", else: "no_verifier"),
      commanded: nil,
      band: nil,
      window: nil,
      targets: [],
      target_count: length(group.targets),
      truncated: false,
      summary: %{met: 0, not_met: 0, pending: 0},
      telemetry: :ok
    }
  end

  defp series(org, mission, group, members, by_request, {position, point, plan}, opts) do
    instances =
      Enum.map(members, &telemetry_instance(Map.get(by_request, &1.command_request_id, [])))

    # An instance has the value it was sent with; before release, the plan's criteria.
    criteria =
      case Enum.find(instances, & &1) do
        nil -> plan && plan.success_criteria
        instance -> instance.success_criteria
      end

    plotted = MapSet.new(members, & &1.group_slot.target_index)
    point_targets = Enum.filter(group.targets, &MapSet.member?(plotted, &1["index"]))
    targets = select_targets(point_targets, Keyword.get(opts, :target_ids))
    window = window(org, mission, members, instances, opts)

    {samples, telemetry} =
      history(org, mission, point.id, Enum.map(targets, & &1["spacecraft_id"]), window, opts)

    by_target =
      Map.new(
        Enum.zip(members, instances),
        &{elem(&1, 0).group_slot.target_index, elem(&1, 1)}
      )

    %{
      verifier: verifier_ref(hd(members)) |> Map.put(:position, position),
      point: point,
      reason: nil,
      commanded: criteria && commanded(criteria),
      band: criteria && band(criteria),
      window: window,
      targets:
        Enum.map(targets, fn target ->
          target["index"]
          |> then(&Map.get(by_target, &1))
          |> instance_fields()
          |> Map.merge(%{
            spacecraft_id: target["spacecraft_id"],
            name: target["name"],
            samples: Map.get(samples, target["spacecraft_id"], [])
          })
        end),
      target_count: length(point_targets),
      truncated: length(targets) < length(point_targets),
      summary: summary(instances),
      telemetry: telemetry
    }
  end

  # A target's verifier instance: its state, which instance and why it failed (U68 R4), and its
  # verify-by and matched times (U69 A4a, "Verify by …" / "Verified at …"). All nil without one.
  defp instance_fields(nil),
    do: %{verifier_state: nil, verifier: nil, timeout_at: nil, matched_at: nil}

  defp instance_fields(instance),
    do: %{
      verifier_state: instance.lifecycle_state,
      verifier: %{
        instance_id: instance.command_verifier_instance_id,
        verifier_id: instance.verifier_id,
        severity: instance.severity,
        failure_code: instance.failure_reason
      },
      timeout_at: instance.timeout_at,
      matched_at: instance.matched_at
    }

  # A verifier's subject is a point id (`telemetry:THERM.setpoint`) or, from the mission model, the
  # parameter's semantic id (`semantic:parameter:…`) or qualified name (#73,
  # `PointCatalog.resolve/2`). Samples, units and types are keyed by the catalog point
  # (`PACKET.field`), so resolve to it first. A subject no active point has stays as is, with unit
  # and type null. `:catalog_fun` (tests): `(-> [point catalog entry])`.
  defp point(org, mission, subject, opts) do
    catalog =
      case Keyword.get(opts, :catalog_fun) do
        nil -> PointCatalog.list_points(org, mission)
        fun -> fun.()
      end

    entry = PointCatalog.resolve(catalog, subject)

    id = if entry, do: entry.point_id, else: subject
    [described] = SpacecraftLive.points(org, mission, [id])

    %{
      id: id,
      name: (entry && (entry.field_name || entry.point_id)) || subject,
      unit: described.unit || (entry && entry.unit),
      type: described.type
    }
  end

  defp telemetry_instance(instances), do: Enum.find(instances, &telemetry_point/1)

  defp verifier_ref(member),
    do: %{
      position: member.group_slot.position,
      command_id: member.command_id,
      command_name: member.command_name
    }

  defp select_targets(targets, nil), do: Enum.take(targets, @max_targets)

  defp select_targets(targets, ids) when is_list(ids) do
    wanted = MapSet.new(ids)

    targets
    |> Enum.filter(&MapSet.member?(wanted, &1["spacecraft_id"]))
    |> Enum.take(@max_targets)
  end

  # From the first release of the plotted command to its last verifier timeout (or now).
  # `:releases_fun` (tests): `(-> [release attempt])`.
  defp window(org, mission, members, instances, opts) do
    ids = MapSet.new(members, & &1.command_request_id)

    attempts =
      case Keyword.get(opts, :releases_fun) do
        nil -> Commanding.list_command_release_attempts(org, mission)
        fun -> fun.()
      end

    released =
      attempts
      |> Enum.filter(&(MapSet.member?(ids, &1.command_request_id) and &1.released_at))
      |> Enum.map(& &1.released_at)

    timeouts =
      instances |> Enum.reject(&is_nil/1) |> Enum.map(& &1.timeout_at) |> Enum.reject(&is_nil/1)

    case released do
      [] ->
        nil

      _some ->
        %{
          from: Enum.min(released, DateTime),
          to: Enum.max(timeouts, DateTime, fn -> DateTime.utc_now() end)
        }
    end
  end

  defp history(_org, _mission, _point_id, _spacecraft_ids, nil, _opts), do: {%{}, :ok}

  # `:history_fun` (tests): `(point_id, spacecraft_id -> [Sample])`.
  defp history(org, mission, point_id, spacecraft_ids, window, opts) do
    read =
      case Keyword.get(opts, :history_fun) do
        nil ->
          &Telemetry.sample_history(org, mission, point_id,
            spacecraft_id: &1,
            from_observed_at: window.from,
            to_observed_at: window.to,
            limit: 10_000
          )

        fun ->
          &fun.(point_id, &1)
      end

    task =
      Task.async(fn ->
        Map.new(spacecraft_ids, fn spacecraft_id ->
          samples = read.(spacecraft_id)

          {spacecraft_id,
           samples |> Enum.filter(&(&1.spacecraft_id == spacecraft_id)) |> decimate()}
        end)
      end)

    case Task.yield(task, @history_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, samples} -> {samples, :ok}
      _slow_or_failed -> {%{}, :degraded}
    end
  end

  defp decimate(samples) do
    step = max(div(length(samples), @max_samples), 1)

    samples
    |> Enum.take_every(step)
    |> Enum.map(
      &%{t: &1.generation_time || &1.receipt_time, value_json: Jason.encode!(value(&1))}
    )
  end

  defp value(%{engineering_value: nil} = sample), do: sample.raw_value
  defp value(sample), do: sample.engineering_value

  defp commanded(%{value: value, comparison: comparison}) when not is_nil(value),
    do: %{value_json: Jason.encode!(unwrap(value)), comparison: comparison}

  defp commanded(_criteria), do: nil

  defp band(%{range_min: min, range_max: max}) when not is_nil(min) or not is_nil(max),
    do: %{
      min_json: min && Jason.encode!(unwrap(min)),
      max_json: max && Jason.encode!(unwrap(max))
    }

  defp band(_criteria), do: nil

  defp unwrap(value), do: JsonDocument.unwrap_value(value)

  defp summary(instances) do
    states = instances |> Enum.reject(&is_nil/1) |> Enum.map(& &1.lifecycle_state)

    %{
      met: Enum.count(states, &(&1 == :satisfied)),
      not_met: Enum.count(states, &(&1 in [:failed, :timed_out])),
      pending: Enum.count(states, &(&1 == :pending))
    }
  end
end
