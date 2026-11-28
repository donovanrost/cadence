defmodule Cadence.Reads.AlarmEvents do
  @moduledoc """
  The runtime's alarm states and transitions as limit events (#451 T3e), for the dashboards'
  limits source: what it asks of `Reads.Limits` (a point's latest state, its event history and the
  watermark of both) answered from `semantic_latest_alarm_states` and `semantic_alarm_transitions`
  instead of the ground limit projections.

  A point is its catalog point (`PointCatalog`); its parameter is what the alarm tables key on (a
  point the catalog does not map is its own parameter). A state or transition becomes a
  `Cadence.Limits.Event` the frame builders already read:

    * `normalized_state` is the alarm level: critical `:red`, caution `:yellow`, normal `:green`;
      a state that raises and clears nothing (`disabled`, `unknown`) is not an event.
    * `limit_event_id` is the transition id; `limit_definition_id` is the policy id; there is no
      limit definition version, set name, evaluated value or raw `limit_state` (a state is written
      on a transition, not with the value that caused it).
    * The history is the TRANSITIONS of the point, not every evaluation.
  """

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Missions
  alias Cadence.Reads.PointParameters
  alias Cadence.Repo
  alias Cadence.SemanticObservations.{AlarmTransitionRow, LatestAlarmStateRow}
  alias Cadence.SemanticRuntime.AlarmLevel

  @default_limit 100

  @doc "The point's latest state on a spacecraft (or the newest of any), as of `to_receipt_time` when given."
  @spec latest_state(binary() | nil, binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(organization_id, mission_id, point_id, opts) do
    organization_id = organization_id || organization_id_for(mission_id)

    case Keyword.get(opts, :to_receipt_time) do
      %DateTime{} ->
        organization_id
        |> history(mission_id, point_id, Keyword.merge(opts, order: :desc, limit: 1))
        |> List.first()

      _now ->
        organization_id
        |> latest_rows(mission_id, point_id, opts)
        |> Enum.map(&state_event/1)
        |> newest()
    end
  end

  @doc "One transition as a limit event, by its id (the id its events carry), for the data links."
  @spec fetch(binary(), binary(), binary()) :: {:ok, Event.t()} | {:error, :limit_event_not_found}
  def fetch(organization_id, mission_id, transition_id) do
    case Repo.get_by(AlarmTransitionRow,
           transition_id: transition_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      nil ->
        {:error, :limit_event_not_found}

      row ->
        point_id = point_for(organization_id, mission_id, row.parameter_id)

        case event(row.transition_id, row, row.to_state, point_id, nil) do
          nil -> {:error, :limit_event_not_found}
          event -> {:ok, event}
        end
    end
  end

  # The catalog point of a parameter; the parameter itself when the catalog does not map it.
  defp point_for(organization_id, mission_id, parameter_id) do
    Map.get(
      PointParameters.mapping(organization_id, mission_id).by_parameter,
      parameter_id,
      parameter_id
    )
  end

  @doc "The point's transitions, `:order` `:asc | :desc` (default newest first), `:limit` (default #{@default_limit})."
  @spec event_history(binary() | nil, binary(), binary(), keyword()) :: [Event.t()]
  def event_history(organization_id, mission_id, point_id, opts) do
    history(organization_id || organization_id_for(mission_id), mission_id, point_id, opts)
  end

  @doc "The watermark of the point's states and transitions, in the shape `Reads.Limits` merges."
  @spec watermark(binary() | nil, binary(), binary(), keyword()) :: %{
          latest: map(),
          events: map()
        }
  def watermark(organization_id, mission_id, point_id, opts) do
    organization_id = organization_id || organization_id_for(mission_id)
    parameters = parameter_ids(organization_id, mission_id, point_id)

    latest =
      LatestAlarmStateRow
      |> tenant(organization_id, mission_id)
      |> where([r], r.parameter_id in ^parameters)
      |> spacecraft(opts)
      |> select([r], %{
        latest_receipt_time: max(r.receipt_time),
        retention_starts_at: min(r.receipt_time),
        sample_count: count(r.id)
      })
      |> Repo.one()

    events =
      AlarmTransitionRow
      |> tenant(organization_id, mission_id)
      |> where([r], r.parameter_id in ^parameters)
      |> spacecraft(opts)
      |> select([r], %{
        latest_receipt_time: max(r.receipt_time),
        retention_starts_at: min(r.receipt_time),
        sample_count: count(r.transition_id)
      })
      |> Repo.one()

    %{latest: latest, events: events}
  end

  defp latest_rows(organization_id, mission_id, point_id, opts) do
    LatestAlarmStateRow
    |> tenant(organization_id, mission_id)
    |> where([r], r.parameter_id in ^parameter_ids(organization_id, mission_id, point_id))
    |> spacecraft(opts)
    |> Repo.all()
    |> Enum.map(&{&1, point_id})
  end

  defp history(organization_id, mission_id, point_id, opts) do
    order = Keyword.get(opts, :order, :desc)
    limit = Keyword.get(opts, :limit, @default_limit)

    AlarmTransitionRow
    |> tenant(organization_id, mission_id)
    |> where([r], r.parameter_id in ^parameter_ids(organization_id, mission_id, point_id))
    |> spacecraft(opts)
    |> from_time(Keyword.get(opts, :from_receipt_time))
    |> to_time(Keyword.get(opts, :to_receipt_time))
    |> order_by([r], [{^order, r.receipt_time}, {^order, r.transition_id}])
    |> limit(^limit)
    |> Repo.all()
    |> Enum.flat_map(&transition_event(&1, point_id))
  end

  # The parameters a point's samples are evaluated as: its catalog parameter, or itself.
  defp parameter_ids(organization_id, mission_id, point_id) do
    case Map.get(PointParameters.mapping(organization_id, mission_id).by_point, point_id) do
      parameter when is_binary(parameter) -> Enum.uniq([parameter, point_id])
      _unmapped -> [point_id]
    end
  end

  # A mission-only caller (no organization) is scoped by the mission alone.
  defp tenant(query, nil, mission_id), do: where(query, [r], r.mission_id == ^mission_id)

  defp tenant(query, organization_id, mission_id),
    do: where(query, [r], r.organization_id == ^organization_id and r.mission_id == ^mission_id)

  defp spacecraft(query, opts) do
    case Keyword.get(opts, :spacecraft_id) do
      nil -> query
      id -> where(query, [r], r.spacecraft_id == ^id)
    end
  end

  defp from_time(query, nil), do: query
  defp from_time(query, at), do: where(query, [r], r.receipt_time >= ^at)

  defp to_time(query, nil), do: query
  defp to_time(query, at), do: where(query, [r], r.receipt_time <= ^at)

  defp newest(events) do
    events |> Enum.reject(&is_nil/1) |> Enum.max_by(& &1.receipt_time, DateTime, fn -> nil end)
  end

  defp state_event({row, point_id}) do
    event(row.transition_id, row, row.effective_state, point_id, row.generation_time)
  end

  defp transition_event(row, point_id) do
    case event(row.transition_id, row, row.to_state, point_id, nil) do
      nil -> []
      event -> [event]
    end
  end

  defp event(id, row, state, point_id, generation_time) do
    case normalized(state) do
      nil ->
        nil

      normalized ->
        %Event{
          limit_event_id: id,
          mission_id: row.mission_id,
          spacecraft_id: row.spacecraft_id,
          point_id: point_id,
          point_name: point_id,
          source_sample_type: :telemetry_sample,
          sample_id: row.evaluation_id,
          limit_definition_id: row.policy_id,
          limit_definition_version: nil,
          limit_set_name: nil,
          evaluated_value: nil,
          limit_state: nil,
          normalized_state: normalized,
          violation: AlarmLevel.alarming?(state),
          generation_time: generation_time,
          receipt_time: row.receipt_time,
          provenance: %{}
        }
    end
  end

  defp normalized(state) do
    case AlarmLevel.level(state) do
      :critical -> :red
      :caution -> :yellow
      :normal -> :green
      :ignore -> nil
    end
  end

  defp organization_id_for(mission_id), do: Missions.organization_id_for_mission(mission_id)
end
