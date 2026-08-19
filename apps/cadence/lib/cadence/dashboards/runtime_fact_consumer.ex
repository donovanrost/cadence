defmodule Cadence.Dashboards.RuntimeFactConsumer do
  @moduledoc """
  Dashboard-owned consumer for committed domain facts that affect runtime data.

  Producers publish facts through their own public boundary. This consumer is
  solely responsible for translating those facts into dashboard cache and
  LiveView invalidation semantics.
  """

  use GenServer

  alias Cadence.Catalog.Revision
  alias Cadence.Contacts.{RealizedContact, ScheduledContact}

  alias Cadence.DataSources.{
    DataBindingEvent,
    DataSourceEvent,
    SourceHealthEvent,
    SourceWatermarkEvent
  }

  alias Cadence.Dashboards.{RuntimeComposition, RuntimeInvalidation}
  alias Cadence.Limits.DefinitionLifecycleEvent

  alias Cadence.Telemetry.{
    BackfillLifecycleChanged,
    ObservationIdentitySelectionChanged,
    ObservationIdentityStateChanged,
    ObservationsCommitted
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    opts = with_configured_defaults(opts)

    :ok = Cadence.Catalog.Facts.subscribe(self())
    :ok = Cadence.Contacts.Facts.subscribe(self())
    :ok = Cadence.DataSources.Facts.subscribe(self())
    :ok = Cadence.Limits.Facts.subscribe(self())
    :ok = Cadence.Telemetry.Facts.subscribe(self())

    {:ok,
     %{
       enabled?: Keyword.fetch!(opts, :enabled?),
       runtime_cache: Keyword.get(opts, :runtime_cache)
     }}
  end

  @impl true
  def handle_call({:cadence_fact, _topic, fact}, _from, state) do
    maybe_consume(fact, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:cadence_fact, _topic, fact}, state) do
    maybe_consume(fact, state)
    {:noreply, state}
  end

  defp maybe_consume(fact, state) do
    if enabled?(state), do: consume(fact, state)
    :ok
  end

  defp consume(%Revision{} = revision, state) do
    RuntimeInvalidation.catalog_revision_changed(
      %{organization_id: revision.organization_id, mission_id: revision.mission_id},
      invalidation_opts(state)
    )
  end

  defp consume(%DefinitionLifecycleEvent{} = event, state) do
    RuntimeInvalidation.limit_definition_changed(
      %{
        organization_id: event.organization_id,
        mission_id: event.mission_id,
        observable: event.point_id,
        limit_set_name: event.limit_set_name,
        scope_type: event.scope_type,
        scope_ref: event.scope_ref,
        realm: event.realm,
        limit_definition_lifecycle_event_id: event.limit_definition_lifecycle_event_id,
        limit_definition_id: event.limit_definition_id,
        limit_definition_version: event.limit_definition_version,
        evidence_ref: %{
          kind: "limit_definition_lifecycle_event",
          id: event.limit_definition_lifecycle_event_id
        }
      },
      invalidation_opts(state)
    )
  end

  defp consume(%DataSourceEvent{} = event, state) do
    RuntimeInvalidation.data_source_binding_changed(
      %{
        organization_id: event.organization_id,
        mission_id: event.mission_id,
        logical_source: logical_source(event.current_adapter),
        data_source_id: event.data_source_id,
        reason: event.event_type,
        evidence_ref: %{
          kind: "data_source_definition_event",
          id: event.data_source_event_id
        }
      },
      invalidation_opts(state)
    )
  end

  defp consume(%DataBindingEvent{} = event, state) do
    RuntimeInvalidation.data_source_binding_changed(
      %{
        organization_id: event.organization_id,
        mission_id: event.mission_id,
        logical_source: event.current_logical_source,
        source_binding_id: event.binding_id,
        data_source_id: event.current_data_source_id,
        realm: event.current_realm,
        dataset: event.current_dataset,
        reason: event.event_type,
        evidence_ref: %{
          kind: "data_source_binding_event",
          id: event.data_binding_event_id
        }
      },
      invalidation_opts(state)
    )
  end

  defp consume(%SourceHealthEvent{} = event, state) do
    RuntimeInvalidation.source_health_changed(
      %{
        organization_id: event.organization_id,
        mission_id: event.mission_id,
        logical_source: event.logical_source,
        data_source_id: event.data_source_id,
        source_binding_id: event.source_binding_id,
        realm: event.realm,
        replay_run_id: event.replay_run_id,
        dataset: event.dataset,
        source_health: event.source_health,
        previous_source_health: event.previous_source_health,
        reason: event.reason,
        observed_at: event.observed_at,
        evidence_ref: %{kind: "data_source_health_event", id: event.source_health_event_id}
      },
      invalidation_opts(state)
    )
  end

  defp consume(%SourceWatermarkEvent{} = event, state) do
    RuntimeInvalidation.source_watermark_changed(
      %{
        organization_id: event.organization_id,
        mission_id: event.mission_id,
        logical_source: event.logical_source,
        data_source_id: event.data_source_id,
        source_binding_id: event.source_binding_id,
        realm: event.realm,
        replay_run_id: event.replay_run_id,
        dataset: event.dataset,
        complete_through: event.complete_through,
        previous_complete_through: event.previous_complete_through,
        latest_receipt_time: event.latest_receipt_time,
        previous_latest_receipt_time: event.previous_latest_receipt_time,
        evidence_ref: %{
          kind: "data_source_watermark_event",
          id: event.source_watermark_event_id
        }
      },
      invalidation_opts(state)
    )
  end

  defp consume(%ObservationsCommitted{} = fact, state) do
    filters = telemetry_filters(fact)

    RuntimeInvalidation.source_watermark_changed(filters, invalidation_opts(state))

    Enum.each(fact.time_ranges, fn time_range ->
      filters
      |> Map.merge(%{
        reason: :telemetry_write,
        time_range: time_range,
        evidence_ref: fact.evidence_ref
      })
      |> RuntimeInvalidation.historical_data_changed(invalidation_opts(state))
    end)
  end

  defp consume(%BackfillLifecycleChanged{} = event, state) do
    event
    |> backfill_filters()
    |> RuntimeInvalidation.historical_data_changed(invalidation_opts(state))
  end

  defp consume(%ObservationIdentitySelectionChanged{} = fact, state) do
    invalidate_revision_state(fact, state)
  end

  defp consume(%ObservationIdentityStateChanged{} = fact, state) do
    invalidate_revision_state(fact, state)
  end

  defp consume(%ScheduledContact{} = contact, state), do: invalidate_events(contact, state)
  defp consume(%RealizedContact{} = contact, state), do: invalidate_events(contact, state)
  defp consume(_fact, _state), do: :ok

  defp invalidate_revision_state(fact, state) do
    filters = %{
      organization_id: fact.organization_id,
      mission_id: fact.mission_id,
      logical_source: :telemetry,
      data_source_id: fact.data_source_id,
      source_binding_id: fact.binding_id,
      realm: fact.realm,
      replay_run_id: fact.replay_run_id,
      observable: fact.point_id,
      observation_identity_id: fact.observation_identity_id
    }

    filters =
      case Map.get(fact, :dependency) do
        dependency when is_map(dependency) ->
          Map.put(filters, :telemetry_revision_dependency, dependency)

        _other ->
          filters
      end

    RuntimeInvalidation.telemetry_revision_state_changed(
      filters,
      invalidation_opts(state)
    )
  end

  defp invalidate_events(contact, state) do
    RuntimeInvalidation.events_changed(
      %{organization_id: contact.organization_id, mission_id: contact.mission_id},
      invalidation_opts(state)
    )
  end

  defp telemetry_filters(%ObservationsCommitted{} = fact) do
    %{
      organization_id: fact.organization_id,
      mission_id: fact.mission_id,
      logical_source: :telemetry,
      data_source_id: fact.data_source_id,
      source_binding_id: fact.binding_id,
      realm: fact.realm,
      replay_run_id: fact.replay_run_id,
      observable: fact.observable_id
    }
  end

  defp backfill_filters(%BackfillLifecycleChanged{} = event) do
    %{
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      logical_source: :telemetry,
      data_source_id: event.data_source_id,
      source_binding_id: event.binding_id,
      realm: event.realm,
      replay_run_id: event.replay_run_id,
      observable: event.observable_id || event.point_id,
      source_from: event.source_from,
      source_to: event.source_to,
      reason: event.reason,
      evidence_ref: %{
        kind: "telemetry_backfill_lifecycle_event",
        id: event.backfill_lifecycle_event_id
      }
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp enabled?(%{enabled?: enabled?}) when is_boolean(enabled?), do: enabled?

  defp invalidation_opts(%{runtime_cache: nil}), do: []

  defp invalidation_opts(%{runtime_cache: runtime_cache}), do: [runtime_cache: runtime_cache]

  defp with_configured_defaults(opts) do
    if Keyword.has_key?(opts, :enabled?) and Keyword.has_key?(opts, :runtime_cache) do
      opts
    else
      composition = RuntimeComposition.from_application()

      opts
      |> Keyword.put_new(:enabled?, composition.runtime_invalidation?)
      |> Keyword.put_new(:runtime_cache, composition.runtime_invalidation_cache)
    end
  end

  defp logical_source(adapter)
       when adapter in [:telemetry, :limits, :operational_observables, :events],
       do: adapter

  defp logical_source(_adapter), do: nil
end
