defmodule Cadence.Reads.SpacecraftUplink do
  @moduledoc """
  Investigate's Uplink tab (ux Investigate.md, Tab · Uplink): "Can I command this spacecraft now,
  and what's going up?" Contract: docs/apogee/api/ops.md.

    * `now`: the live commandable pass (`in_contact: true`) or the next one, with its readiness.
    * `next_passes`: up to 3 more commandable passes in the next 24 h, with uplink evidence.
    * `queue`: the spacecraft's lane in release order; `waits_for` is the pass its head releases on.
    * `released`: releases on its lane in the last 24 h, newest first.
    * `route`: the primary active uplink routing rule.
  """

  alias Cadence.Commanding
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.Contacts.UplinkPasses
  alias Cadence.Control.UplinkReadiness
  alias Cadence.Control.UplinkReadiness.Attention, as: UplinkBlocked
  alias Cadence.Reads.{CommandGroups, Commands, PassUplink}
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @horizon_s 24 * 3_600
  @next_passes 3
  @open_entries [:pending, :release_pending]

  @spec load(binary(), binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(org, mission, spacecraft_id, opts \\ []) do
    with {:ok, craft} <- spacecraft(org, mission, spacecraft_id) do
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      lanes = lanes(org, mission, spacecraft_id)
      {current, upcoming} = passes(org, mission, spacecraft_id, now)
      refs = PassUplink.pass_refs(org, mission, Enum.reject([current | upcoming], &is_nil/1))
      readiness = readiness(org, mission, current, refs)
      now_view = now_view(current, readiness, refs, now)

      {:ok,
       %{
         spacecraft: %{id: craft.spacecraft_id, name: craft.display_name, scid: craft.scid},
         route: route(org, mission, craft),
         now: now_view,
         next_passes: next_passes(upcoming, current, refs, now),
         queue: queue(org, mission, lanes),
         waits_for: now_view && %{pass: now_view.pass, readiness: now_view.readiness},
         released: released(org, mission, lanes, now)
       }}
    end
  end

  defp spacecraft(org, mission, spacecraft_id) do
    case SpacecraftStore.fetch_spacecraft(org, mission, spacecraft_id) do
      {:ok, craft} -> {:ok, craft}
      _missing -> {:error, :spacecraft_not_found}
    end
  end

  # The live commandable pass (a readiness entry whose pass hasn't ended), and the upcoming ones.
  defp passes(org, mission, spacecraft_id, now) do
    live =
      org
      |> UplinkReadiness.live(mission)
      |> Enum.filter(
        &(&1.spacecraft_id == spacecraft_id and DateTime.compare(&1.ends_at, now) == :gt)
      )
      |> Enum.min_by(& &1.starts_at, DateTime, fn -> nil end)

    upcoming =
      org
      |> UplinkPasses.upcoming(mission, [spacecraft_id], now, @next_passes + 1)
      |> Map.get(spacecraft_id, [])

    case live do
      nil ->
        {List.first(upcoming), Enum.drop(upcoming, 1)}

      live ->
        {live, Enum.reject(upcoming, &(&1.scheduled_contact_id == live.scheduled_contact_id))}
    end
  end

  defp readiness(_org, _mission, nil, _refs), do: nil

  # The same object as a /passes row's `uplink_readiness` (with `command_groups_queued`), from the
  # pass's row where there is one (it carries the reservation a dropped uplink is read from).
  defp readiness(org, mission, pass, refs) do
    blocked =
      org
      |> UplinkBlocked.items(mission)
      |> Map.new(&{&1.contact_id, &1})

    row = Map.get(refs.rows, pass.scheduled_contact_id) || pass
    [%{uplink_readiness: readiness}] = PassUplink.put_readiness(org, mission, [row], blocked)
    readiness
  end

  defp now_view(nil, _readiness, _refs, _now), do: nil

  defp now_view(pass, readiness, refs, now) do
    %{
      in_contact: DateTime.compare(pass.starts_at, now) != :gt,
      pass: pass_view(pass, refs),
      readiness: readiness
    }
  end

  defp next_passes(upcoming, _current, refs, now) do
    horizon = DateTime.add(now, @horizon_s)

    upcoming
    |> Enum.filter(&(DateTime.compare(&1.starts_at, horizon) == :lt))
    |> Enum.take(@next_passes)
    |> Enum.map(&Map.merge(pass_view(&1, refs), evidence(&1, refs)))
  end

  defp pass_view(pass, refs) do
    row = Map.get(refs.rows, pass.scheduled_contact_id)

    pass
    |> Map.put_new(:ground_station_ref, nil)
    |> PassUplink.pass_ref(refs)
    |> Map.put(:provider, row && %{id: row.source.provider, name: row.source.provider_name})
  end

  # U32 / #46: the provider confirmed the uplink leg, or an operator attested the booking; with
  # the /passes row's `uplink_confirmed` and `attested_by`.
  defp evidence(pass, refs) do
    row = Map.get(refs.rows, pass.scheduled_contact_id)

    %{
      uplink_evidence:
        if(row && row.booking_evidence == "operator_attested", do: "attested", else: "booked"),
      uplink_confirmed: row && row.uplink_confirmed,
      attested_by: row && row.attested_by
    }
  end

  # Every command endpoint of the spacecraft is its own lane (the managed one among them).
  defp lanes(org, mission, spacecraft_id) do
    org
    |> SourceEndpoints.list_source_endpoints(mission, spacecraft_id: spacecraft_id)
    |> Enum.map(& &1.source_endpoint_id)
    |> MapSet.new()
    |> MapSet.put(SourceEndpoints.managed_source_endpoint_id(spacecraft_id))
  end

  defp queue(org, mission, lanes) do
    entries =
      org
      |> Commanding.list_command_queue_entries(mission)
      |> Enum.filter(
        &(MapSet.member?(lanes, &1.queue_lane_key) and &1.lifecycle_state in @open_entries)
      )
      |> Enum.sort_by(&{&1.priority, &1.queue_sequence})

    requests = requests(org, mission, lanes)
    groups = group_titles(org, mission, Map.values(requests))

    entries
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {entry, position} ->
      case Map.get(requests, entry.command_request_id) do
        nil ->
          []

        request ->
          [
            %{
              position: position,
              request_id: request.command_request_id,
              command_id: request.command_id,
              command_name: request.command_name,
              arguments_json: Jason.encode!(request.argument_values || %{}),
              group: group_ref(request, groups),
              not_before: request.not_before,
              expires_at: request.expires_at,
              queued_at: entry.enqueued_at
            }
          ]
      end
    end)
  end

  defp released(org, mission, lanes, now) do
    since = DateTime.add(now, -@horizon_s)

    attempts =
      org
      |> Commanding.list_command_release_attempts(mission)
      |> Enum.filter(fn attempt ->
        MapSet.member?(lanes, attempt.source_endpoint_ref) and attempt.released_at != nil and
          DateTime.compare(attempt.released_at, since) != :lt
      end)

    requests = requests(org, mission, lanes)

    released_requests =
      attempts |> Enum.map(&Map.get(requests, &1.command_request_id)) |> Enum.reject(&is_nil/1)

    rows = status_rows(org, mission, released_requests)
    groups = group_titles(org, mission, released_requests)

    attempts
    |> Enum.sort_by(& &1.released_at, {:desc, DateTime})
    |> Enum.map(fn attempt ->
      request = Map.get(requests, attempt.command_request_id)
      row = Map.get(rows, attempt.command_request_id)

      %{
        request_id: attempt.command_request_id,
        command_name: attempt.command_name,
        group: request && group_ref(request, groups),
        released_at: attempt.released_at,
        contact_id: attempt.realized_contact_id,
        status: row && to_string(row.status),
        verification_state: row && to_string(CommandGroups.row_stage(row))
      }
    end)
  end

  defp requests(org, mission, lanes) do
    org
    |> Commanding.list_command_requests(mission)
    |> Enum.filter(&MapSet.member?(lanes, &1.source_endpoint_ref))
    |> Map.new(&{&1.command_request_id, &1})
  end

  defp status_rows(_org, _mission, []), do: %{}

  defp status_rows(org, mission, requests) do
    org
    |> Commands.snapshot(mission,
      requests: fn _org, _mission, _opts -> requests end,
      target_names: fn _, _, _ -> %{} end
    )
    |> Map.fetch!(:rows)
    |> Map.new(&{&1.command_request_id, &1})
  end

  defp group_titles(org, mission, requests) do
    requests
    |> Enum.map(&get_in(&1.metadata || %{}, ["group", "id"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case GroupStore.fetch(org, mission, id) do
        {:ok, group} -> {id, group.title}
        _missing -> {id, nil}
      end
    end)
  end

  defp group_ref(request, groups) do
    case get_in(request.metadata || %{}, ["group", "id"]) do
      nil -> nil
      id -> %{id: id, title: Map.get(groups, id)}
    end
  end

  defp route(org, mission, craft) do
    org
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission, craft.spacecraft_id)
    |> Enum.find(
      &(&1.lifecycle_state == :active and &1.enabled? and &1.role == :primary and
          &1.direction in [:outbound, :bidirectional])
    )
    |> case do
      nil ->
        nil

      rule ->
        %{
          routing_rule_id: rule.routing_rule_id,
          name: rule.display_name,
          transport_id: rule.transport_id,
          transport_name: transport_name(org, mission, rule.transport_id),
          gateway_scid: craft.scid
        }
    end
  end

  defp transport_name(org, mission, transport_id) do
    case TransportStore.fetch_transport(org, mission, transport_id) do
      {:ok, transport} -> transport.display_name
      _missing -> nil
    end
  end
end
