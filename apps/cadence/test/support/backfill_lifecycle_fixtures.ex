defmodule Cadence.BackfillLifecycleFixtures do
  @moduledoc """
  Inserts telemetry backfill lifecycle events, with their operational event, for tests of the
  readers that remain. Cadence stopped recording these when historical data operations were
  retired (#702); the dashboards events products and the data-link resolver still read the rows.
  """

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Platform.EventBus
  alias Cadence.Repo
  alias Cadence.Telemetry.Facts
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow

  @spec record_backfill_lifecycle_event(map(), keyword()) ::
          {:ok, BackfillLifecycleEvent.t()} | {:error, term()}
  def record_backfill_lifecycle_event(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    event = BackfillLifecycleEvent.new(attrs)

    with {:ok, event} <- insert(event) do
      if Keyword.get(
           opts,
           :publish_facts?,
           Keyword.get(opts, :dashboard_runtime_invalidation?, true)
         ) do
        Facts.publish(
          Keyword.get(opts, :event_bus, EventBus),
          BackfillLifecycleEvent.to_fact(event)
        )
      end

      {:ok, event}
    end
  end

  defp insert(%BackfillLifecycleEvent{} = event) do
    Repo.transaction(fn ->
      with {:ok, row} <- event |> EventRow.changeset() |> Repo.insert(),
           persisted = EventRow.to_domain(row),
           {:ok, %OperationalEvent{}} <-
             persisted
             |> OperationalEvent.from_backfill_lifecycle_event()
             |> then(&OperationalEvents.persist_event(Repo, &1)) do
        persisted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
