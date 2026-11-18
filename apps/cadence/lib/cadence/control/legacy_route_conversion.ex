defmodule Cadence.Control.LegacyRouteConversion do
  @moduledoc """
  TEMPORARY (deleted with 9ac6dc8ee, the legacy routing save's removal): converts a mission's
  legacy per-spacecraft routing rules into extra routes (`spacecraft_route`), through ordinary
  change sets (director 11-16, lead).

  Faithful: ONE extra route per legacy rule, with its transport pinned, its direction and role,
  and its name and purpose as written, so the routing plan and what operators see are unchanged.
  Each op carries `replaces: [rule id]`; the kind refuses unless the route's legs are exactly the
  rule, and archives the rule in the same apply transaction (never both, never neither).

  In BATCHES of N craft (default 50, 1..100), in a stable order (spacecraft id). A batch stands
  alone in the mission's open change set (`Staging`: staged only into an empty set, one at a time,
  nothing beside it), and its apply always needs an independent approval (`Submission`: approval
  forced, so `reviewer_is_author` refuses the stager). A legacy rule whose transport has no
  station can't be mapped: it's skipped and reported, never blocks the batch.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.Configuration.{ChangeRow, ChangeSetStore, Staging}
  alias Cadence.Control.Configuration
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @default_batch 50
  @batch_sizes 1..100
  @source_key "legacy_route_conversion"
  @listed_unmappable 50

  @doc "The default and allowed batch sizes (spacecraft per batch)."
  def batch_sizes, do: %{default: @default_batch, range: @batch_sizes}

  @doc """
  Where the conversion stands, for the console's callout (operate_mission):
  `%{routes_converted, routes_total, batch_size, batches_total, next_batch, staged_batch,
  unmappable: %{count, routes}, can_stage}`. `next_batch` is nil while a batch is staged or when
  nothing is left to stage; `staged_batch` is `%{change_set_id, batch, author}` or nil.
  """
  @spec progress(Scope.t(), String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def progress(%Scope{} = scope, mission_id, batch_size \\ @default_batch) do
    with {:ok, mission} <- authorize(scope, mission_id, :operate_mission) do
      org = mission.organization_id
      state = state(org, mission_id)
      staged = staged_batch(mission_id)
      applied = applied_batches(mission_id)
      remaining = Map.keys(state.mappable) |> length()

      {:ok,
       %{
         routes_converted: state.converted,
         routes_total: state.converted + state.legacy_count,
         batch_size: batch_size,
         batches_total: applied + ceil_div(remaining, batch_size),
         next_batch: if(is_nil(staged) and remaining > 0, do: applied + 1),
         staged_batch: staged,
         unmappable: %{
           count: length(state.unmappable),
           routes: state.unmappable |> describe(org, mission_id) |> Enum.take(@listed_unmappable)
         },
         can_stage: allowed?(scope, mission, :manage_mission)
       }}
    end
  end

  @doc """
  Stages the NEXT batch of `spacecraft` craft (1..100, default 50) into the mission's open change
  set, as the caller (manage_mission). Returns `%{change_set_id, batch, batches_total,
  route_count, spacecraft_count, remaining_route_count, unmappable}` (this batch's skipped
  routes). Errors: `{:invalid_params, :spacecraft}`, `:nothing_to_convert`,
  `{:conversion_already_staged, %{change_set_id, batch, author}}`,
  `{:open_change_set_not_empty, change_set_id}`, `:frozen_in_review`, `:forbidden`.
  """
  @spec stage_next_batch(Scope.t(), String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def stage_next_batch(scope, mission_id, spacecraft \\ @default_batch)

  def stage_next_batch(%Scope{} = scope, mission_id, spacecraft)
      when is_integer(spacecraft) and spacecraft in @batch_sizes do
    with {:ok, mission} <- authorize(scope, mission_id, :manage_mission),
         :ok <- set_free(mission_id) do
      org = mission.organization_id
      state = state(org, mission_id)
      picked = state.mappable |> Enum.sort_by(&elem(&1, 0)) |> Enum.take(spacecraft)
      stage_batch(scope, org, mission_id, state, picked, spacecraft)
    end
  end

  def stage_next_batch(%Scope{}, _mission_id, _spacecraft),
    do: {:error, {:invalid_params, :spacecraft}}

  @doc "The batch a change set holds, `%{batch, batches_total}`, or nil (not a conversion)."
  @spec change_set_batch(String.t(), String.t()) :: map() | nil
  def change_set_batch(mission_id, change_set_id) do
    with {:ok, set} <- ChangeSetStore.fetch(mission_id, change_set_id),
         %{} = source <- conversion_source(ChangeSetStore.changes(set.change_set_id, states())) do
      %{batch: source["batch"], batches_total: source["batches_total"]}
    else
      _none -> nil
    end
  end

  defp stage_batch(_scope, _org, _mission_id, _state, [], _size),
    do: {:error, :nothing_to_convert}

  defp stage_batch(scope, org, mission_id, state, picked, size) do
    batch = applied_batches(mission_id) + 1
    batches_total = batch - 1 + ceil_div(map_size(state.mappable), size)
    rules = Enum.flat_map(picked, &elem(&1, 1))
    craft = MapSet.new(picked, &elem(&1, 0))
    skipped = Enum.filter(state.unmappable, &MapSet.member?(craft, &1.rule.spacecraft_id))

    attrs = %{
      summary:
        "Converted from the old routing page: batch #{batch} of #{batches_total}, " <>
          "#{length(rules)} routes on #{length(picked)} spacecraft.",
      source: %{@source_key => %{"batch" => batch, "batches_total" => batches_total}}
    }

    with {:ok, staged} <- Configuration.stage(scope, mission_id, attrs, Enum.map(rules, &op/1)) do
      {:ok,
       %{
         change_set_id: staged.change_set_id,
         batch: batch,
         batches_total: batches_total,
         route_count: length(rules),
         spacecraft_count: length(picked),
         remaining_route_count: state.legacy_count - length(rules),
         unmappable: describe(skipped, org, mission_id)
       }}
    end
  end

  # One extra route per legacy rule: its transport pinned, its leg, its name and purpose.
  defp op(%{rule: rule, station: station}) do
    leg = if rule.direction == :inbound, do: "downlink", else: "uplink"

    %{
      kind: "spacecraft_route",
      action: "create",
      document:
        %{
          "spacecraft_id" => rule.spacecraft_id,
          "ground_station_id" => station,
          "transport_id" => rule.transport_id,
          "downlink" => "none",
          "uplink" => "none",
          "display_name" => rule.display_name,
          "purpose_label" => rule.purpose_label
        }
        |> Map.put(leg, Atom.to_string(rule.role))
        |> Map.reject(fn {_key, value} -> is_nil(value) end),
      options: %{"replaces" => [rule.routing_rule_id]}
    }
  end

  # The mission's active legacy rules, mappable (grouped by craft) or not; the converted count.
  defp state(org, mission_id) do
    rules = RoutingRuleStore.list_routing_rules(org, mission_id)
    legacy = Enum.filter(rules, &(&1.origin == :legacy and &1.lifecycle_state == :active))
    stations = transport_stations(org, mission_id)

    {mappable, unmappable} =
      legacy
      |> Enum.map(&%{rule: &1, station: Map.get(stations, &1.transport_id)})
      |> Enum.split_with(&is_binary(&1.station))

    %{
      legacy_count: length(legacy),
      converted: Enum.count(rules, &converted?/1),
      mappable: Enum.group_by(mappable, & &1.rule.spacecraft_id),
      unmappable: Enum.sort_by(unmappable, & &1.rule.spacecraft_id)
    }
  end

  defp converted?(rule),
    do:
      rule.origin == :spacecraft and rule.lifecycle_state == :active and
        is_list((rule.metadata || %{})["converted_from"])

  defp transport_stations(org, mission_id) do
    for transport <- TransportStore.list_transports(org, mission_id),
        is_binary(transport.ground_station_id),
        into: %{},
        do: {transport.transport_id, transport.ground_station_id}
  end

  defp describe(entries, org, mission_id) do
    names = Map.new(SpacecraftStore.list_spacecraft(org, mission_id), &{&1.spacecraft_id, &1})

    entries
    |> Enum.map(fn %{rule: rule} ->
      %{
        routing_rule_id: rule.routing_rule_id,
        reason: "transport_has_no_station",
        spacecraft: %{
          id: rule.spacecraft_id,
          name: names |> Map.get(rule.spacecraft_id) |> then(&(&1 && &1.display_name))
        }
      }
    end)
    |> Enum.sort_by(&{is_nil(&1.spacecraft.name), &1.spacecraft.name, &1.routing_rule_id})
  end

  # One batch at a time, alone in its set (Staging refuses the same, under its lock; this answers
  # with the details first).
  defp set_free(mission_id) do
    case ChangeSetStore.active(mission_id) do
      nil ->
        :ok

      %{state: "in_review"} ->
        {:error, :frozen_in_review}

      set ->
        changes = ChangeSetStore.changes(set.change_set_id)

        cond do
          batch = staged_batch(mission_id) -> {:error, {:conversion_already_staged, batch}}
          changes != [] -> {:error, {:open_change_set_not_empty, set.change_set_id}}
          true -> :ok
        end
    end
  end

  defp staged_batch(mission_id) do
    with %{} = set <- ChangeSetStore.active(mission_id),
         [%ChangeRow{} = change | _] <-
           Enum.filter(ChangeSetStore.changes(set.change_set_id), &Staging.conversion?(&1.source)) do
      author = change.author || %{}

      %{
        change_set_id: set.change_set_id,
        batch: change.source[@source_key]["batch"],
        author: %{id: author["id"], name: author["name"]}
      }
    else
      _none -> nil
    end
  end

  defp applied_batches(mission_id) do
    ChangeRow
    |> where(
      [change],
      change.mission_id == ^mission_id and change.state == "applied" and
        fragment("(? -> ?) IS NOT NULL", change.source, ^@source_key)
    )
    |> select([change], count(change.change_set_id, :distinct))
    |> Repo.one()
  end

  defp conversion_source(changes) do
    Enum.find_value(changes, &(Staging.conversion?(&1.source) && &1.source[@source_key]))
  end

  defp states, do: ["staged", "applied"]

  defp authorize(%Scope{organization_id: org} = scope, mission_id, action) do
    with {:ok, mission} <- Missions.fetch_mission(org, mission_id),
         :ok <- policy(scope, mission, action),
         do: {:ok, mission}
  end

  # todo(authz): Cedar should decide who may stage the conversion (manage_mission today).
  defp policy(scope, mission, action) do
    case Policy.authorize(scope, action, %{
           organization_id: mission.organization_id,
           mission_id: mission.mission_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp allowed?(scope, mission, action), do: policy(scope, mission, action) == :ok

  defp ceil_div(0, _size), do: 0
  defp ceil_div(count, size), do: div(count + size - 1, size)
end
