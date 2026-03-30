defmodule Cadence.Reads.Limits do
  @moduledoc """
  Read-side queries for canonical limit events and latest limit-state
  projection.
  """

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Persistence.Schemas.{TelemetryLatestLimitStateRow, TelemetryLimitEventRow}
  alias Cadence.Repo

  @mission_scope_key "__mission__"

  @spec latest_state(binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    TelemetryLatestLimitStateRow
    |> where([state_row], state_row.mission_id == ^mission_id and state_row.point_id == ^point_id)
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], desc: state_row.receipt_time, desc: state_row.limit_event_id)
    |> limit(1)
    |> Repo.one()
    |> maybe_to_event()
  end

  @spec latest_state(binary(), binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    TelemetryLatestLimitStateRow
    |> where(
      [state_row],
      state_row.organization_id == ^organization_id and state_row.mission_id == ^mission_id and
        state_row.point_id == ^point_id
    )
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], desc: state_row.receipt_time, desc: state_row.limit_event_id)
    |> limit(1)
    |> Repo.one()
    |> maybe_to_event()
  end

  @spec latest_states_for_mission(binary(), keyword()) :: [Event.t()]
  def latest_states_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    TelemetryLatestLimitStateRow
    |> where([state_row], state_row.mission_id == ^mission_id)
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], asc: state_row.point_name)
    |> Repo.all()
    |> Enum.map(&TelemetryLatestLimitStateRow.to_domain/1)
  end

  @spec latest_states_for_mission(binary(), binary(), keyword()) :: [Event.t()]
  def latest_states_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    TelemetryLatestLimitStateRow
    |> where(
      [state_row],
      state_row.organization_id == ^organization_id and state_row.mission_id == ^mission_id
    )
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], asc: state_row.point_name)
    |> Repo.all()
    |> Enum.map(&TelemetryLatestLimitStateRow.to_domain/1)
  end

  @spec event_history(binary(), binary(), keyword()) :: [Event.t()]
  def event_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)

    TelemetryLimitEventRow
    |> where([event_row], event_row.mission_id == ^mission_id and event_row.point_id == ^point_id)
    |> maybe_filter_event_spacecraft(spacecraft_id)
    |> order_history(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&TelemetryLimitEventRow.to_domain/1)
  end

  @spec event_history(binary(), binary(), binary(), keyword()) :: [Event.t()]
  def event_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)

    TelemetryLimitEventRow
    |> where(
      [event_row],
      event_row.organization_id == ^organization_id and event_row.mission_id == ^mission_id and
        event_row.point_id == ^point_id
    )
    |> maybe_filter_event_spacecraft(spacecraft_id)
    |> order_history(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&TelemetryLimitEventRow.to_domain/1)
  end

  defp maybe_filter_latest_spacecraft(query, spacecraft_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(
        query,
        [state_row],
        state_row.spacecraft_scope_id == ^spacecraft_scope_id(spacecraft_id)
      )
    else
      query
    end
  end

  defp maybe_filter_event_spacecraft(query, nil), do: query

  defp maybe_filter_event_spacecraft(query, spacecraft_id),
    do: where(query, [event_row], event_row.spacecraft_id == ^spacecraft_id)

  defp order_history(query, :asc),
    do: order_by(query, [event_row], asc: event_row.receipt_time, asc: event_row.limit_event_id)

  defp order_history(query, _order),
    do: order_by(query, [event_row], desc: event_row.receipt_time, desc: event_row.limit_event_id)

  defp maybe_to_event(nil), do: nil

  defp maybe_to_event(%TelemetryLatestLimitStateRow{} = state_row),
    do: TelemetryLatestLimitStateRow.to_domain(state_row)

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id
end
