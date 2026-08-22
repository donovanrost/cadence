defmodule Cadence.Limits.Store do
  @moduledoc "Data-plane persistence boundary for limit events and latest limit states."

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.{LatestStateRow, LimitEventRow}
  alias Cadence.Repo
  alias Cadence.Telemetry.LatestProjectionOrder
  alias Ecto.Multi

  @mission_scope_key "__mission__"

  @spec add_event_inserts(Multi.t(), [Event.t()]) :: Multi.t()
  def add_event_inserts(%Multi{} = multi, events) when is_list(events) do
    Enum.reduce(events, multi, fn %Event{} = event, acc ->
      Multi.insert(
        acc,
        {:limit_event, event.limit_event_id},
        LimitEventRow.changeset(event),
        on_conflict: :nothing,
        conflict_target: [:limit_event_id]
      )
    end)
  end

  @spec persist_latest_states(module(), [Event.t()]) :: {:ok, [struct()]} | {:error, term()}
  def persist_latest_states(repo, events) when is_list(events) do
    Enum.reduce_while(events, {:ok, []}, fn %Event{} = event, {:ok, acc} ->
      case persist_latest_state(repo, event) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec fetch_event(binary(), binary(), binary()) :: {:ok, Event.t()} | {:error, :not_found}
  def fetch_event(organization_id, mission_id, event_id) do
    LimitEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.limit_event_id == ^event_id
    )
    |> Repo.one()
    |> case do
      %LimitEventRow{} = row -> {:ok, LimitEventRow.to_domain(row)}
      nil -> {:error, :not_found}
    end
  end

  @spec list_events(binary(), keyword()) :: [Event.t()]
  def list_events(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    LimitEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter(:point_id, Keyword.get(opts, :point_id))
    |> maybe_filter(:sample_id, Keyword.get(opts, :sample_id))
    |> maybe_filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_enum(:source_sample_type, Keyword.get(opts, :source_sample_type))
    |> maybe_filter_from(Keyword.get(opts, :from_receipt_time))
    |> maybe_filter_to(Keyword.get(opts, :to_receipt_time))
    |> order_events(Keyword.get(opts, :order, :desc))
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(&LimitEventRow.to_domain/1)
  end

  @spec list_latest_states(binary(), keyword()) :: [Event.t()]
  def list_latest_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    LatestStateRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter(:point_id, Keyword.get(opts, :point_id))
    |> maybe_filter_in(:point_id, Keyword.get(opts, :point_ids))
    |> maybe_filter_latest_spacecraft(Keyword.get(opts, :spacecraft_id), opts)
    |> maybe_filter_in(:spacecraft_scope_id, Keyword.get(opts, :spacecraft_scope_ids))
    |> order_latest(Keyword.get(opts, :order, :point_name))
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(&LatestStateRow.to_domain/1)
  end

  @spec replace_latest_states(binary(), [Event.t()], keyword()) :: :ok | {:error, term()}
  def replace_latest_states(mission_id, events, opts \\ [])
      when is_binary(mission_id) and is_list(events) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    Repo.transaction(fn ->
      LatestStateRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_rebuild_spacecraft(spacecraft_id)
      |> Repo.delete_all()

      Enum.each(events, fn %Event{} = event ->
        %LatestStateRow{} |> LatestStateRow.changeset(event) |> Repo.insert!()
      end)
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec watermark(binary(), binary(), keyword()) :: map()
  def watermark(mission_id, point_id, opts \\ []) do
    latest =
      LatestStateRow
      |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
      |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
      |> maybe_filter_latest_spacecraft(Keyword.get(opts, :spacecraft_id), opts)
      |> projection_watermark(:id)
      |> Repo.one()

    events =
      LimitEventRow
      |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
      |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
      |> maybe_filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
      |> projection_watermark(:limit_event_id)
      |> Repo.one()

    %{latest: latest, events: events}
  end

  defp persist_latest_state(repo, %Event{} = event) do
    existing =
      repo.get_by(LatestStateRow,
        mission_id: event.mission_id,
        spacecraft_scope_id: spacecraft_scope_id(event.spacecraft_id),
        point_id: event.point_id
      )

    cond do
      is_nil(existing) ->
        %LatestStateRow{} |> LatestStateRow.changeset(event) |> repo.insert()

      LatestProjectionOrder.newer?(event, existing, :limit_event_id) ->
        existing |> LatestStateRow.changeset(event) |> repo.update()

      true ->
        {:ok, existing}
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp maybe_filter_enum(query, _field, nil), do: query

  defp maybe_filter_enum(query, field, value) do
    normalized = to_string(value)
    where(query, [row], field(row, ^field) == ^normalized)
  end

  defp maybe_filter_in(query, _field, nil), do: query
  defp maybe_filter_in(query, _field, []), do: where(query, false)

  defp maybe_filter_in(query, field, values),
    do: where(query, [row], field(row, ^field) in ^values)

  defp maybe_filter_from(query, nil), do: query

  defp maybe_filter_from(query, %DateTime{} = value),
    do: where(query, [row], row.receipt_time >= ^value)

  defp maybe_filter_to(query, nil), do: query

  defp maybe_filter_to(query, %DateTime{} = value),
    do: where(query, [row], row.receipt_time <= ^value)

  defp maybe_filter_latest_spacecraft(query, spacecraft_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      scope_id = spacecraft_scope_id(spacecraft_id)
      where(query, [row], row.spacecraft_scope_id == ^scope_id)
    else
      query
    end
  end

  defp maybe_filter_rebuild_spacecraft(query, nil), do: query

  defp maybe_filter_rebuild_spacecraft(query, spacecraft_id),
    do: where(query, [row], row.spacecraft_scope_id == ^spacecraft_id)

  defp order_events(query, :asc),
    do: order_by(query, [row], asc: row.receipt_time, asc: row.limit_event_id)

  defp order_events(query, _order),
    do: order_by(query, [row], desc: row.receipt_time, desc: row.limit_event_id)

  defp order_latest(query, :desc),
    do: order_by(query, [row], desc: row.receipt_time, desc: row.limit_event_id)

  defp order_latest(query, _order), do: order_by(query, [row], asc: row.point_name)

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  defp projection_watermark(query, count_field) do
    select(query, [row], %{
      latest_receipt_time: max(row.receipt_time),
      retention_starts_at: min(row.receipt_time),
      sample_count: count(field(row, ^count_field))
    })
  end

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id
end
