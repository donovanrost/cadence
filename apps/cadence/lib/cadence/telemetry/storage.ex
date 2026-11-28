defmodule Cadence.Telemetry.Storage do
  @moduledoc """
  Canonical telemetry observation history write path.

  This module converts telemetry samples into storage observation envelopes and
  dispatches them to the configured physical writer.
  """

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.DataSources.Watermarks, as: SourceWatermarks

  alias Cadence.Telemetry.Storage.{
    BackfillLifecycleEvent,
    BackfillLifecycleEvents,
    ObservationEnvelope,
    ObservationIdentityDecisionEvent,
    ObservationIdentityState,
    ObservationIdentityStates,
    WatermarkCoalescer,
    WriteContext
  }

  alias Cadence.Telemetry.{CurrentValueStore, Facts, ObservationsCommitted, Sample}

  @default_realm :flight
  @default_data_source_id "managed_questdb_primary"
  @default_binding_id "default_flight_telemetry"
  @default_writer Cadence.Telemetry.Storage.Writers.QuestDB

  @type policy :: %{
          required(:writer) => module(),
          required(:writer_opts) => keyword(),
          required(:storage_opts) => keyword(),
          required(:current_value_store_policy) => CurrentValueStore.policy(),
          required(:event_bus) => EventBus.server()
        }

  @doc """
  Builds a writer child spec from the current application configuration.

  This compatibility arity reads application configuration when called. The
  supervised runtime uses `child_spec/1` with a policy captured at startup.
  """
  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec, do: child_spec(configured_policy())

  @spec child_spec(policy()) :: Supervisor.child_spec() | nil
  def child_spec(%{writer: writer, writer_opts: writer_opts}) do
    writer = ensure_writer_loaded!(writer)

    if function_exported?(writer, :child_spec, 1) do
      writer.child_spec(writer_opts)
    end
  end

  @doc """
  Persists samples using the current application configuration.

  Prefer `persist_samples/3` for internal workflows that own a captured storage
  policy.
  """
  @spec persist_samples([Sample.t()], keyword()) :: :ok | {:error, term()}
  def persist_samples(samples, opts \\ []) when is_list(samples) and is_list(opts) do
    policy = %{configured_policy() | event_bus: Keyword.get(opts, :event_bus, EventBus)}
    persist_samples(policy, samples, opts)
  end

  @spec persist_samples(policy(), [Sample.t()], keyword()) :: :ok | {:error, term()}
  def persist_samples(%{} = policy, samples, opts)
      when is_list(samples) and is_list(opts) do
    opts = with_event_bus(opts, policy.event_bus)

    samples
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while(:ok, fn {_mission_id, mission_samples}, :ok ->
      case persist_mission_samples(policy, mission_samples, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Writes the pending source-watermark window of a mission (the end-of-pass flush of #690): the
  data plane's entry point for callers outside it, so the coalescer's own module stays internal.
  """
  @spec flush_source_watermarks(binary() | nil) :: :ok | {:error, term()}
  def flush_source_watermarks(mission_id), do: WatermarkCoalescer.flush_mission(mission_id)

  @doc "Writes the pending source-watermark window of one status row."
  @spec flush_source_watermark(binary()) :: :ok | {:error, term()}
  def flush_source_watermark(source_watermark_key),
    do: WatermarkCoalescer.flush_key(source_watermark_key)

  @spec enrich_samples([Sample.t()], keyword()) :: {:ok, [Sample.t()]} | {:error, term()}
  def enrich_samples(samples, opts \\ []) when is_list(samples) and is_list(opts) do
    enrich_samples(configured_policy(), samples, opts)
  end

  @spec enrich_samples(policy(), [Sample.t()], keyword()) ::
          {:ok, [Sample.t()]} | {:error, term()}
  def enrich_samples(%{} = policy, samples, opts)
      when is_list(samples) and is_list(opts) do
    samples
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while({:ok, []}, fn {_mission_id, mission_samples}, {:ok, acc} ->
      case enrich_mission_samples(policy, mission_samples, opts) do
        {:ok, enriched_samples} -> {:cont, {:ok, acc ++ enriched_samples}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec persist_prepared_results([map()], keyword()) :: :ok | {:error, term()}
  def persist_prepared_results(prepared_results, opts \\ [])
      when is_list(prepared_results) and is_list(opts) do
    policy = %{configured_policy() | event_bus: Keyword.get(opts, :event_bus, EventBus)}
    persist_prepared_results(policy, prepared_results, opts)
  end

  @spec persist_prepared_results(policy(), [map()], keyword()) :: :ok | {:error, term()}
  def persist_prepared_results(%{} = policy, prepared_results, opts)
      when is_list(prepared_results) and is_list(opts) do
    opts = with_event_bus(opts, policy.event_bus)

    with {:ok, envelopes} <- prepared_envelopes(policy, prepared_results, opts) do
      persist_envelope_groups(policy, envelopes, opts)
    end
  end

  defp persist_envelope_groups(policy, envelopes, opts) do
    envelopes
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while(:ok, fn {_mission_id, mission_envelopes}, :ok ->
      case persist_envelopes_and_publish(policy, mission_envelopes, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp prepared_envelopes(policy, prepared_results, opts) do
    prepared_results
    |> Enum.reduce_while({:ok, []}, fn prepared_result, {:ok, batches} ->
      samples = Map.get(prepared_result, :telemetry_samples, [])

      write_opts =
        opts
        |> Keyword.put_new(:source_endpoint_id, source_endpoint_id(prepared_result))
        |> Keyword.put_new(:recorded_at, recorded_at(prepared_result))

      case envelopes_for_samples(policy, samples, write_opts) do
        {:ok, envelopes} -> {:cont, {:ok, [envelopes | batches]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, batches} -> {:ok, batches |> Enum.reverse() |> List.flatten()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp envelopes_for_samples(policy, samples, opts) do
    samples
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while({:ok, []}, fn {_mission_id, samples}, {:ok, acc} ->
      with {:ok, context} <- write_context(policy, List.first(samples), opts),
           {:ok, envelopes} <- ObservationEnvelope.batch_from_samples(context, samples, opts) do
        {:cont, {:ok, acc ++ envelopes}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec fetch_observation_identity_state(binary()) ::
          {:ok, ObservationIdentityState.t()} | {:error, term()}
  def fetch_observation_identity_state(observation_identity_id)
      when is_binary(observation_identity_id) do
    ObservationIdentityStates.fetch(observation_identity_id)
  end

  @spec fetch_observation_identity_states([binary()], keyword()) :: [ObservationIdentityState.t()]
  def fetch_observation_identity_states(observation_identity_ids, opts)
      when is_list(observation_identity_ids) and is_list(opts) do
    ObservationIdentityStates.fetch_many(observation_identity_ids, opts)
  end

  @spec apply_observation_identity_decision(binary(), atom(), keyword()) ::
          {:ok, ObservationIdentityState.t()} | {:error, term()}
  def apply_observation_identity_decision(observation_identity_id, decision, opts)
      when is_binary(observation_identity_id) and is_atom(decision) and is_list(opts) do
    ObservationIdentityStates.apply_decision(
      observation_identity_id,
      decision,
      Keyword.put_new(opts, :event_bus, EventBus)
    )
  end

  @spec list_observation_identity_decision_events(binary(), keyword()) :: [
          ObservationIdentityDecisionEvent.t()
        ]
  def list_observation_identity_decision_events(observation_identity_id, opts)
      when is_binary(observation_identity_id) and is_list(opts) do
    ObservationIdentityStates.list_decision_events(observation_identity_id, opts)
  end

  @spec list_observation_identity_decision_events_for_mission(binary(), keyword()) :: [
          ObservationIdentityDecisionEvent.t()
        ]
  def list_observation_identity_decision_events_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    ObservationIdentityStates.list_scoped_decision_events(mission_id, opts)
  end

  @spec fetch_observation_identity_decision_event(binary(), keyword()) ::
          ObservationIdentityDecisionEvent.t() | nil
  def fetch_observation_identity_decision_event(decision_event_id, opts \\ [])
      when is_binary(decision_event_id) and is_list(opts) do
    ObservationIdentityStates.fetch_decision_event(decision_event_id, opts)
  end

  @spec list_observation_identity_states(binary(), keyword()) :: [ObservationIdentityState.t()]
  def list_observation_identity_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    ObservationIdentityStates.list(mission_id, opts)
  end

  @spec list_backfill_lifecycle_events(binary(), keyword()) :: [BackfillLifecycleEvent.t()]
  def list_backfill_lifecycle_events(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    BackfillLifecycleEvents.list_events(mission_id, opts)
  end

  @spec fetch_backfill_lifecycle_event(binary(), keyword()) :: BackfillLifecycleEvent.t() | nil
  def fetch_backfill_lifecycle_event(backfill_lifecycle_event_id, opts \\ [])
      when is_binary(backfill_lifecycle_event_id) and is_list(opts) do
    BackfillLifecycleEvents.fetch_event(backfill_lifecycle_event_id, opts)
  end

  @spec writer_module() :: module()
  def writer_module, do: configured_policy().writer

  @spec writer_module(policy()) :: module()
  def writer_module(%{writer: writer}), do: writer

  @doc false
  @spec policy(keyword() | map(), keyword()) :: policy()
  def policy(config, opts \\ [])
      when (is_list(config) or is_map(config)) and is_list(opts) do
    config = if is_map(config), do: Map.to_list(config), else: config

    %{
      writer: Keyword.get(config, :writer, @default_writer),
      writer_opts: Keyword.get(config, :writer_opts, []),
      storage_opts: Keyword.drop(config, [:writer, :writer_opts]),
      current_value_store_policy:
        Keyword.get_lazy(opts, :current_value_store_policy, fn ->
          CurrentValueStore.configured_policy()
        end),
      event_bus: Keyword.get(opts, :event_bus, EventBus)
    }
  end

  @doc false
  @spec configured_policy() :: policy()
  def configured_policy do
    policy(Application.get_env(:cadence, :telemetry_storage, []),
      current_value_store_policy: CurrentValueStore.configured_policy()
    )
  end

  @doc """
  Seeds the current-value store with samples that are already known (the latest values a starting
  partition reads back from the history store, DECISIONS #96, #831), exactly as ingest would have recorded them (same source identity, so
  they share the live samples' keys) but with nothing else: no observation is written, no fact is
  published. The samples keep their OWN generation and receipt times, so staleness stays honest,
  and the store keeps a newer value it already has.
  """
  @spec seed_current_values(policy(), [Sample.t()], keyword()) :: :ok | {:error, term()}
  def seed_current_values(_policy, [], _opts), do: :ok

  def seed_current_values(policy, [%Sample{} | _rest] = samples, opts) when is_list(opts) do
    with {:ok, enriched} <- enrich_mission_samples(policy, samples, opts) do
      CurrentValueStore.record_samples(policy.current_value_store_policy, enriched)
    end
  end

  defp persist_mission_samples(_policy, [], _opts), do: :ok

  defp persist_mission_samples(policy, [%Sample{} | _rest] = samples, opts) do
    with {:ok, context} <- write_context(policy, List.first(samples), opts),
         {:ok, envelopes} <- ObservationEnvelope.batch_from_samples(context, samples, opts) do
      persist_envelopes_and_publish(policy, envelopes, opts)
    end
  end

  defp persist_envelopes_and_publish(policy, envelopes, opts) do
    with :ok <- persist_mission_envelopes(policy, envelopes, opts) do
      publish_observation_facts(policy, envelopes, opts)
    end
  end

  defp persist_mission_envelopes(policy, envelopes, opts) do
    case writer_module(policy).persist_envelopes(envelopes, policy.writer_opts) do
      :ok -> persist_mission_envelope_projections(policy, envelopes, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_mission_envelope_projections(policy, envelopes, opts) do
    with :ok <- ObservationIdentityStates.record_envelopes(envelopes, opts),
         :ok <- record_current_values(policy, envelopes, opts) do
      record_data_source_watermarks(envelopes, opts)
    end
  end

  defp enrich_mission_samples(_policy, [], _opts), do: {:ok, []}

  defp enrich_mission_samples(policy, [%Sample{} | _rest] = samples, opts) do
    with {:ok, context} <- write_context(policy, List.first(samples), opts),
         {:ok, envelopes} <- ObservationEnvelope.batch_from_samples(context, samples, opts) do
      {:ok, Enum.map(envelopes, &ObservationEnvelope.to_sample/1)}
    end
  end

  defp record_current_values(policy, envelopes, opts) do
    if Keyword.get(opts, :record_current_values?, true) do
      CurrentValueStore.record_samples(
        policy.current_value_store_policy,
        Enum.map(envelopes, &ObservationEnvelope.to_sample/1)
      )
    else
      :ok
    end
  end

  defp record_data_source_watermarks([], _opts), do: :ok

  defp record_data_source_watermarks(envelopes, opts) do
    if SourceWatermarks.enabled?(opts) do
      record_data_source_watermark_groups(envelopes, opts)
    else
      :ok
    end
  end

  defp record_data_source_watermark_groups(envelopes, opts) do
    attributes =
      envelopes
      |> Enum.group_by(&source_watermark_group_key/1)
      |> Enum.map(fn {_group_key, group} -> source_watermark_attrs(group) end)

    # Merged in memory and written in bulk (#690): no database work, and no row shared by paths.
    Enum.each(attributes, &WatermarkCoalescer.observe(&1, opts))
  end

  defp write_context(policy, %Sample{mission_id: mission_id}, opts) do
    storage_config = policy.storage_opts

    WriteContext.new(
      organization_id: organization_id(policy, mission_id, opts),
      mission_id: mission_id,
      realm: Keyword.get(opts, :realm, Keyword.get(storage_config, :realm, @default_realm)),
      data_source_id:
        Keyword.get(
          opts,
          :data_source_id,
          Keyword.get(storage_config, :data_source_id, @default_data_source_id)
        ),
      binding_id:
        Keyword.get(
          opts,
          :binding_id,
          Keyword.get(storage_config, :binding_id, @default_binding_id)
        ),
      source_endpoint_id: Keyword.get(opts, :source_endpoint_id),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      recorded_at: Keyword.get(opts, :recorded_at),
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  defp organization_id(policy, mission_id, opts) do
    Keyword.get(opts, :organization_id) ||
      OrganizationScope.organization_id_for_mission(mission_id) ||
      Keyword.get(policy.storage_opts, :organization_id)
  end

  defp source_endpoint_id(%{raw_evidence: %RawEvidence{} = raw_evidence}) do
    raw_evidence.source_endpoint_ref || raw_evidence.source_ref
  end

  defp source_endpoint_id(_prepared_result), do: nil

  defp recorded_at(%{raw_evidence: %RawEvidence{} = raw_evidence}), do: raw_evidence.receipt_time
  defp recorded_at(_prepared_result), do: nil

  defp publish_observation_facts(_policy, [], _opts), do: :ok

  defp publish_observation_facts(policy, envelopes, opts) do
    if publish_observation_facts?(policy, opts) do
      envelopes
      |> Enum.group_by(&invalidation_group_key/1)
      |> Enum.each(fn {_group_key, group} ->
        publish_observation_fact(policy.event_bus, group)
      end)
    end

    :ok
  end

  defp publish_observation_facts?(policy, opts) do
    Keyword.get(
      opts,
      :publish_facts?,
      Keyword.get(
        opts,
        :dashboard_runtime_invalidation?,
        Keyword.get(policy.storage_opts, :dashboard_runtime_invalidation?, true)
      )
    )
  end

  defp invalidation_group_key(%ObservationEnvelope{} = envelope) do
    {
      envelope.organization_id,
      envelope.mission_id,
      envelope.data_source_id,
      envelope.binding_id,
      envelope.realm,
      envelope.replay_run_id,
      envelope.observable_id
    }
  end

  defp source_watermark_group_key(%ObservationEnvelope{} = envelope) do
    {
      envelope.organization_id,
      envelope.mission_id,
      envelope.data_source_id,
      envelope.binding_id,
      envelope.realm,
      envelope.replay_run_id
    }
  end

  defp publish_observation_fact(
         event_bus,
         [%ObservationEnvelope{} = first_envelope | _rest] = envelopes
       ) do
    Facts.publish(event_bus, %ObservationsCommitted{
      organization_id: first_envelope.organization_id,
      mission_id: first_envelope.mission_id,
      data_source_id: first_envelope.data_source_id,
      binding_id: first_envelope.binding_id,
      realm: first_envelope.realm,
      replay_run_id: first_envelope.replay_run_id,
      observable_id: first_envelope.observable_id,
      time_ranges: changed_time_ranges(envelopes),
      evidence_ref: telemetry_write_evidence_ref(envelopes),
      committed_at: latest_datetime(Enum.map(envelopes, & &1.ingested_at))
    })
  end

  defp source_watermark_attrs([%ObservationEnvelope{} = first_envelope | _rest] = envelopes) do
    receipt_times = Enum.map(envelopes, & &1.receipt_time)

    {retention_starts_at, latest_receipt_time} =
      Enum.min_max_by(receipt_times, &DateTime.to_unix(&1, :microsecond))

    observed_at = latest_datetime(Enum.map(envelopes, & &1.ingested_at))

    %{
      organization_id: first_envelope.organization_id,
      mission_id: first_envelope.mission_id,
      logical_source: :telemetry,
      data_source_id: first_envelope.data_source_id,
      source_binding_id: first_envelope.binding_id,
      realm: first_envelope.realm,
      replay_run_id: first_envelope.replay_run_id,
      dataset: dataset_for_realm(first_envelope.realm),
      complete_through: latest_receipt_time,
      latest_receipt_time: latest_receipt_time,
      retention_starts_at: retention_starts_at,
      sample_count: length(envelopes),
      confidence: :best_effort,
      reason: :telemetry_storage_write,
      observed_at: observed_at,
      payload: telemetry_write_evidence_ref(envelopes)
    }
  end

  defp changed_time_ranges(envelopes) do
    [
      changed_time_range(envelopes, :receipt_time),
      changed_time_range(envelopes, :generation_time)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp changed_time_range(envelopes, axis) do
    envelopes
    |> Enum.map(&Map.get(&1, axis))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      times ->
        {from, to} = Enum.min_max_by(times, &DateTime.to_unix(&1, :microsecond))
        %{axis: axis, from: from, to: to}
    end
  end

  # The batch's count and its first and last sample, not every sample id: the full list (~12 KB
  # per write) went into both watermark tables and nothing read it (disk, 11-16; api, ux and
  # dashboards confirmed no reader).
  defp telemetry_write_evidence_ref(envelopes) do
    first_envelope = List.first(envelopes)
    last_envelope = List.last(envelopes)

    %{
      kind: "telemetry_storage_write",
      observation_count: length(envelopes),
      first_sample_id: first_envelope && first_envelope.sample_id,
      last_sample_id: last_envelope && last_envelope.sample_id,
      replay_run_id: first_envelope && first_envelope.replay_run_id
    }
  end

  defp latest_datetime(datetimes) do
    datetimes
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> DateTime.utc_now() end)
  end

  defp dataset_for_realm(realm) when is_atom(realm), do: Atom.to_string(realm)
  defp dataset_for_realm(realm), do: realm

  defp ensure_writer_loaded!(writer) when is_atom(writer) do
    case Code.ensure_loaded(writer) do
      {:module, ^writer} ->
        writer

      {:error, reason} ->
        raise "could not load telemetry storage writer #{inspect(writer)}: #{inspect(reason)}"
    end
  end

  defp with_event_bus(opts, event_bus) when is_list(opts) do
    Keyword.put(opts, :event_bus, event_bus)
  end
end
