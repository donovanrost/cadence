defmodule Cadence.Telemetry.Storage.BackfillLifecycleEvents do
  @moduledoc """
  Persistence boundary for telemetry backfill/import lifecycle events.
  """

  import Ecto.Query

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Platform.EventBus

  alias Cadence.Repo
  alias Cadence.Telemetry.Facts
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent

  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow,
    as: TelemetryBackfillLifecycleEventRow

  @spec record_event(map(), keyword()) ::
          {:ok, BackfillLifecycleEvent.t()} | {:error, term()}
  def record_event(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    event_bus = Keyword.get(opts, :event_bus, Map.get(attrs, :event_bus, EventBus))
    event = BackfillLifecycleEvent.new(attrs)

    case insert_event_with_operational_event(event) do
      {:ok, event} ->
        maybe_publish_fact(event_bus, event, opts)
        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list_events(binary(), keyword()) :: [BackfillLifecycleEvent.t()]
  def list_events(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    if required_context?(Keyword.put(opts, :mission_id, mission_id)) do
      TelemetryBackfillLifecycleEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> filter(:organization_id, Keyword.get(opts, :organization_id))
      |> filter(:realm, Keyword.get(opts, :realm))
      |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
      |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
      |> filter(:binding_id, Keyword.get(opts, :binding_id))
      |> filter(:observable_id, Keyword.get(opts, :observable_id))
      |> filter(:point_id, Keyword.get(opts, :point_id))
      |> filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
      |> filter(:event_type, Keyword.get(opts, :event_type))
      |> filter(:authority, Keyword.get(opts, :authority))
      |> filter(:backfill_run_id, Keyword.get(opts, :backfill_run_id))
      |> maybe_from_occurred_at(Keyword.get(opts, :from_occurred_at))
      |> maybe_to_occurred_at(Keyword.get(opts, :to_occurred_at))
      |> maybe_source_overlaps(Keyword.get(opts, :source_from), Keyword.get(opts, :source_to))
      |> order_by([row], asc: row.occurred_at, asc: row.backfill_lifecycle_event_id)
      |> limit(^result_limit(opts))
      |> Repo.all()
      |> Enum.map(&TelemetryBackfillLifecycleEventRow.to_domain/1)
    else
      []
    end
  end

  @spec fetch_event(binary(), keyword()) :: BackfillLifecycleEvent.t() | nil
  def fetch_event(backfill_lifecycle_event_id, opts \\ [])
      when is_binary(backfill_lifecycle_event_id) and is_list(opts) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)

    if required_context?(opts) do
      TelemetryBackfillLifecycleEventRow
      |> where(
        [row],
        row.backfill_lifecycle_event_id == ^backfill_lifecycle_event_id and
          row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )
      |> Repo.one()
      |> case do
        %TelemetryBackfillLifecycleEventRow{} = row ->
          TelemetryBackfillLifecycleEventRow.to_domain(row)

        nil ->
          nil
      end
    end
  end

  defp insert_event_with_operational_event(%BackfillLifecycleEvent{} = event) do
    Repo.transaction(fn ->
      with {:ok, row} <-
             event
             |> TelemetryBackfillLifecycleEventRow.changeset()
             |> Repo.insert(),
           persisted_event = TelemetryBackfillLifecycleEventRow.to_domain(row),
           {:ok, %OperationalEvent{}} <-
             persisted_event
             |> OperationalEvent.from_backfill_lifecycle_event()
             |> then(&OperationalEvents.persist_event(Repo, &1)) do
        persisted_event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_publish_fact(event_bus, %BackfillLifecycleEvent{} = event, opts) do
    if Keyword.get(
         opts,
         :publish_facts?,
         Keyword.get(opts, :dashboard_runtime_invalidation?, true)
       ) do
      Facts.publish(event_bus, BackfillLifecycleEvent.to_fact(event))
    end

    :ok
  end

  defp required_context?(opts) do
    present?(Keyword.get(opts, :organization_id)) and present?(Keyword.get(opts, :mission_id))
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp filter(query, _field, nil), do: query

  defp filter(query, field, value) do
    normalized_value = enum_string(value)
    where(query, [row], field(row, ^field) == ^normalized_value)
  end

  defp maybe_from_occurred_at(query, %DateTime{} = from_occurred_at) do
    where(query, [row], row.occurred_at >= ^from_occurred_at)
  end

  defp maybe_from_occurred_at(query, _from_occurred_at), do: query

  defp maybe_to_occurred_at(query, %DateTime{} = to_occurred_at) do
    where(query, [row], row.occurred_at < ^to_occurred_at)
  end

  defp maybe_to_occurred_at(query, _to_occurred_at), do: query

  defp maybe_source_overlaps(query, %DateTime{} = source_from, %DateTime{} = source_to) do
    where(
      query,
      [row],
      is_nil(row.source_to) or is_nil(row.source_from) or
        (row.source_from < ^source_to and row.source_to > ^source_from)
    )
  end

  defp maybe_source_overlaps(query, _source_from, _source_to), do: query

  defp result_limit(opts) do
    opts
    |> Keyword.get(:limit, 500)
    |> min(1_000)
    |> max(1)
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
