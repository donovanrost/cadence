defmodule Cadence.Telemetry.Storage do
  @moduledoc """
  Canonical telemetry observation history write path.

  This module converts telemetry samples into storage observation envelopes and
  dispatches them to the configured physical writer.
  """

  alias Cadence.Dashboards.{RuntimeInvalidation, SourceWatermarks}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Telemetry.{CurrentValueStore, Sample}

  alias Cadence.Telemetry.Storage.{
    BackfillLifecycleEvent,
    BackfillLifecycleEvents,
    BackfillLifecycleWorkflow,
    ObservationEnvelope,
    ObservationIdentityDecisionEvent,
    ObservationIdentityState,
    ObservationIdentityStates,
    WriteContext
  }

  @default_realm :flight
  @default_data_source_id "managed_questdb_primary"
  @default_binding_id "default_flight_telemetry"

  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec do
    writer = ensure_writer_loaded!(writer_module())

    if function_exported?(writer, :child_spec, 1) do
      writer.child_spec(writer_opts())
    end
  end

  @spec persist_samples([Sample.t()], keyword()) :: :ok | {:error, term()}
  def persist_samples(samples, opts \\ []) when is_list(samples) and is_list(opts) do
    samples
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while(:ok, fn {_mission_id, mission_samples}, :ok ->
      case persist_mission_samples(mission_samples, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec enrich_samples([Sample.t()], keyword()) :: {:ok, [Sample.t()]} | {:error, term()}
  def enrich_samples(samples, opts \\ []) when is_list(samples) and is_list(opts) do
    samples
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while({:ok, []}, fn {_mission_id, mission_samples}, {:ok, acc} ->
      case enrich_mission_samples(mission_samples, opts) do
        {:ok, enriched_samples} -> {:cont, {:ok, acc ++ enriched_samples}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec persist_prepared_results([map()], keyword()) :: :ok | {:error, term()}
  def persist_prepared_results(prepared_results, opts \\ [])
      when is_list(prepared_results) and is_list(opts) do
    Enum.reduce_while(prepared_results, :ok, fn prepared_result, :ok ->
      samples = Map.get(prepared_result, :telemetry_samples, [])

      write_opts =
        opts
        |> Keyword.put_new(:source_endpoint_id, source_endpoint_id(prepared_result))
        |> Keyword.put_new(:recorded_at, recorded_at(prepared_result))

      case persist_samples(samples, write_opts) do
        :ok -> {:cont, :ok}
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
    ObservationIdentityStates.apply_decision(observation_identity_id, decision, opts)
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

  @spec record_backfill_lifecycle_event(map(), keyword()) ::
          {:ok, BackfillLifecycleEvent.t()} | {:error, term()}
  def record_backfill_lifecycle_event(attrs, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    BackfillLifecycleEvents.record_event(attrs, opts)
  end

  @spec record_backfill_lifecycle_workflow_event(
          atom() | binary(),
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, BackfillLifecycleEvent.t()} | {:error, term()}
  def record_backfill_lifecycle_workflow_event(workflow, stage, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_map(attrs) and is_list(opts) do
    BackfillLifecycleWorkflow.record_event(workflow, stage, attrs, opts)
  end

  @spec execute_backfill_lifecycle_workflow(
          atom() | binary(),
          map(),
          keyword(),
          (keyword() -> term()),
          keyword()
        ) :: term() | {:error, term()}
  def execute_backfill_lifecycle_workflow(workflow, attrs, write_opts, operation_fun, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(write_opts) and
             is_function(operation_fun, 1) and is_list(opts) do
    BackfillLifecycleWorkflow.execute(workflow, attrs, write_opts, operation_fun, opts)
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
  def writer_module do
    Application.get_env(:cadence, :telemetry_storage, [])
    |> Keyword.get(:writer, Cadence.Telemetry.Storage.Writers.QuestDB)
  end

  defp persist_mission_samples([], _opts), do: :ok

  defp persist_mission_samples([%Sample{} | _rest] = samples, opts) do
    with {:ok, context} <- write_context(List.first(samples), opts),
         {:ok, envelopes} <- ObservationEnvelope.batch_from_samples(context, samples, opts),
         :ok <- persist_mission_envelopes_or_record_failure(envelopes, opts),
         :ok <- record_backfill_lifecycle_events(envelopes, opts) do
      invalidate_dashboard_runtime_caches(envelopes, opts)
    end
  end

  defp persist_mission_envelopes_or_record_failure(envelopes, opts) do
    case persist_mission_envelopes(envelopes, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        _result = record_failed_backfill_lifecycle_events(envelopes, opts, reason)
        {:error, reason}
    end
  end

  defp persist_mission_envelopes(envelopes, opts) do
    case writer_module().persist_envelopes(envelopes, writer_opts()) do
      :ok -> persist_mission_envelope_projections(envelopes, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_mission_envelope_projections(envelopes, opts) do
    with :ok <- ObservationIdentityStates.record_envelopes(envelopes, opts),
         :ok <- record_current_values(envelopes, opts) do
      record_dashboard_source_watermarks(envelopes, opts)
    end
  end

  defp enrich_mission_samples([], _opts), do: {:ok, []}

  defp enrich_mission_samples([%Sample{} | _rest] = samples, opts) do
    with {:ok, context} <- write_context(List.first(samples), opts),
         {:ok, envelopes} <- ObservationEnvelope.batch_from_samples(context, samples, opts) do
      {:ok, Enum.map(envelopes, &ObservationEnvelope.to_sample/1)}
    end
  end

  defp record_current_values(envelopes, opts) do
    if Keyword.get(opts, :record_current_values?, true) do
      envelopes
      |> Enum.map(&ObservationEnvelope.to_sample/1)
      |> CurrentValueStore.record_samples()
    else
      :ok
    end
  end

  defp record_dashboard_source_watermarks([], _opts), do: :ok

  defp record_dashboard_source_watermarks(envelopes, opts) do
    if SourceWatermarks.enabled?(opts) do
      record_dashboard_source_watermark_groups(envelopes, opts)
    else
      :ok
    end
  end

  defp record_dashboard_source_watermark_groups(envelopes, opts) do
    envelopes
    |> Enum.group_by(&invalidation_group_key/1)
    |> Enum.reduce_while(:ok, fn {_group_key, group}, :ok ->
      case SourceWatermarks.maybe_record_source_watermark(
             source_watermark_attrs(group),
             Keyword.put(opts, :invalidate_runtime_cache?, false)
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp record_backfill_lifecycle_events([], _opts), do: :ok

  defp record_backfill_lifecycle_events(envelopes, opts) do
    if backfill_lifecycle_event_enabled?(opts) do
      do_record_backfill_lifecycle_events(envelopes, opts)
    else
      :ok
    end
  end

  defp do_record_backfill_lifecycle_events(envelopes, opts) do
    envelopes
    |> Enum.group_by(&backfill_lifecycle_group_key/1)
    |> Enum.reduce_while(:ok, fn {_group_key, group}, :ok ->
      reduce_backfill_lifecycle_event_group(group, opts)
    end)
  end

  defp reduce_backfill_lifecycle_event_group(group, opts) do
    case BackfillLifecycleEvents.record_event(
           backfill_lifecycle_event_attrs(group, opts),
           Keyword.take(opts, [:runtime_cache, :dashboard_runtime_invalidation?])
         ) do
      {:ok, _event} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp record_failed_backfill_lifecycle_events([], _opts, _reason), do: :ok

  defp record_failed_backfill_lifecycle_events(envelopes, opts, reason) do
    if backfill_lifecycle_event_enabled?(opts) do
      envelopes
      |> Enum.group_by(&backfill_lifecycle_group_key/1)
      |> Enum.each(fn {_group_key, group} ->
        _result =
          BackfillLifecycleEvents.record_event(
            backfill_lifecycle_event_attrs(group, opts,
              event_type: failed_backfill_lifecycle_event_type(opts),
              reason: failed_backfill_lifecycle_reason(opts),
              payload: %{"error" => inspect(reason)}
            ),
            Keyword.take(opts, [:runtime_cache, :dashboard_runtime_invalidation?])
          )
      end)
    end

    :ok
  end

  defp write_context(%Sample{mission_id: mission_id}, opts) do
    storage_config = storage_config()

    WriteContext.new(
      organization_id: organization_id(mission_id, opts),
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

  defp organization_id(mission_id, opts) do
    Keyword.get(opts, :organization_id) ||
      OrganizationScope.organization_id_for_mission(mission_id) ||
      Keyword.get(storage_config(), :organization_id)
  end

  defp source_endpoint_id(%{raw_evidence: %RawEvidence{} = raw_evidence}) do
    raw_evidence.source_endpoint_ref || raw_evidence.source_ref
  end

  defp source_endpoint_id(_prepared_result), do: nil

  defp recorded_at(%{raw_evidence: %RawEvidence{} = raw_evidence}), do: raw_evidence.receipt_time
  defp recorded_at(_prepared_result), do: nil

  defp invalidate_dashboard_runtime_caches([], _opts), do: :ok

  defp invalidate_dashboard_runtime_caches(envelopes, opts) do
    if dashboard_runtime_invalidation_enabled?(opts) do
      runtime_cache = dashboard_runtime_cache(opts)

      envelopes
      |> Enum.group_by(&invalidation_group_key/1)
      |> Enum.each(fn {_group_key, group} ->
        invalidate_dashboard_runtime_cache_group(group, runtime_cache)
      end)
    end

    :ok
  end

  defp dashboard_runtime_invalidation_enabled?(opts) do
    Keyword.get(
      opts,
      :dashboard_runtime_invalidation?,
      Keyword.get(storage_config(), :dashboard_runtime_invalidation?, true)
    )
  end

  defp dashboard_runtime_cache(opts) do
    Keyword.get(
      opts,
      :dashboard_runtime_cache,
      Keyword.get(storage_config(), :dashboard_runtime_cache, Cadence.Dashboards.RuntimeCache)
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

  defp backfill_lifecycle_group_key(%ObservationEnvelope{} = envelope) do
    {
      envelope.organization_id,
      envelope.mission_id,
      envelope.data_source_id,
      envelope.binding_id,
      envelope.realm,
      envelope.replay_run_id,
      envelope.observable_id,
      envelope.point_id,
      envelope.spacecraft_id
    }
  end

  defp invalidate_dashboard_runtime_cache_group(
         [%ObservationEnvelope{} = first_envelope | _rest] = envelopes,
         runtime_cache
       ) do
    filters = dashboard_invalidation_filters(first_envelope)
    opts = [runtime_cache: runtime_cache]

    _live_result = RuntimeInvalidation.source_watermark_changed(filters, opts)

    envelopes
    |> changed_time_ranges()
    |> Enum.each(fn time_range ->
      filters
      |> Map.merge(%{
        reason: :telemetry_write,
        time_range: time_range,
        evidence_ref: telemetry_write_evidence_ref(envelopes)
      })
      |> RuntimeInvalidation.historical_data_changed(opts)
    end)
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

  defp dashboard_invalidation_filters(%ObservationEnvelope{} = envelope) do
    %{
      organization_id: envelope.organization_id,
      mission_id: envelope.mission_id,
      logical_source: :telemetry,
      data_source_id: envelope.data_source_id,
      source_binding_id: envelope.binding_id,
      realm: envelope.realm,
      replay_run_id: envelope.replay_run_id,
      observable: envelope.observable_id
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

  defp telemetry_write_evidence_ref(envelopes) do
    first_envelope = List.first(envelopes)

    %{
      kind: "telemetry_storage_write",
      observation_count: length(envelopes),
      sample_ids: Enum.map(envelopes, & &1.sample_id),
      replay_run_id: first_envelope && first_envelope.replay_run_id
    }
  end

  defp backfill_lifecycle_event_enabled?(opts) do
    case Keyword.fetch(opts, :record_backfill_lifecycle_event?) do
      {:ok, enabled?} ->
        enabled?

      :error ->
        present?(Keyword.get(opts, :backfill_run_id)) or
          present?(Keyword.get(opts, :import_run_id))
    end
  end

  defp backfill_lifecycle_event_attrs(
         [%ObservationEnvelope{} = first_envelope | _rest] = envelopes,
         opts,
         overrides \\ []
       ) do
    {source_from, source_to} = source_time_range(envelopes)
    {receipt_from, receipt_to} = receipt_time_range(envelopes)

    %{
      backfill_run_id: backfill_run_id(opts),
      organization_id: first_envelope.organization_id,
      mission_id: first_envelope.mission_id,
      realm: first_envelope.realm,
      replay_run_id: first_envelope.replay_run_id,
      data_source_id: first_envelope.data_source_id,
      binding_id: first_envelope.binding_id,
      observable_id: first_envelope.observable_id,
      point_id: first_envelope.point_id,
      spacecraft_id: first_envelope.spacecraft_id,
      event_type:
        Keyword.get(overrides, :event_type) || backfill_lifecycle_event_type(first_envelope, opts),
      source_from: source_from,
      source_to: source_to,
      receipt_from: receipt_from,
      receipt_to: receipt_to,
      sample_count: length(envelopes),
      authority: backfill_lifecycle_authority(first_envelope, opts),
      reason: Keyword.get(overrides, :reason) || backfill_lifecycle_reason(first_envelope, opts),
      actor_id: Keyword.get(opts, :actor_id) || Keyword.get(opts, :operator_id),
      actor_kind: Keyword.get(opts, :actor_kind),
      occurred_at: latest_datetime(Enum.map(envelopes, & &1.ingested_at)),
      payload: backfill_lifecycle_payload(envelopes, opts, Keyword.get(overrides, :payload, %{}))
    }
  end

  defp backfill_run_id(opts) do
    Keyword.get(opts, :backfill_run_id) || Keyword.get(opts, :import_run_id)
  end

  defp backfill_lifecycle_event_type(_first_envelope, opts) do
    Keyword.get(opts, :backfill_lifecycle_event_type) ||
      Keyword.get(opts, :telemetry_backfill_event_type) ||
      Keyword.get(opts, :event_type) ||
      default_backfill_lifecycle_event_type(opts)
  end

  defp default_backfill_lifecycle_event_type(opts) do
    cond do
      Keyword.get(opts, :late_data?, false) -> :late_data_accepted
      present?(Keyword.get(opts, :import_run_id)) -> :import_completed
      true -> :backfill_completed
    end
  end

  defp failed_backfill_lifecycle_event_type(opts) do
    cond do
      Keyword.get(opts, :late_data?, false) -> :late_data_rejected
      present?(Keyword.get(opts, :import_run_id)) -> :import_failed
      true -> :backfill_failed
    end
  end

  defp backfill_lifecycle_authority(%ObservationEnvelope{validity_state: :advisory}, opts) do
    Keyword.get(opts, :authority, :advisory)
  end

  defp backfill_lifecycle_authority(_first_envelope, opts) do
    Keyword.get(opts, :authority, :authoritative)
  end

  defp backfill_lifecycle_reason(first_envelope, opts) do
    Keyword.get(opts, :reason) || default_backfill_lifecycle_reason(first_envelope, opts)
  end

  defp default_backfill_lifecycle_reason(_first_envelope, opts) do
    cond do
      Keyword.get(opts, :late_data?, false) -> :late_data_write
      present?(Keyword.get(opts, :import_run_id)) -> :telemetry_import_write
      true -> :telemetry_backfill_write
    end
  end

  defp failed_backfill_lifecycle_reason(opts) do
    cond do
      Keyword.get(opts, :late_data?, false) -> :late_data_write_failed
      present?(Keyword.get(opts, :import_run_id)) -> :telemetry_import_write_failed
      true -> :telemetry_backfill_write_failed
    end
  end

  defp backfill_lifecycle_payload(envelopes, opts, extra_payload) do
    %{
      "kind" => "telemetry_storage_write",
      "sample_ids" => Enum.map(envelopes, & &1.sample_id),
      "observation_ids" => Enum.map(envelopes, & &1.observation_id),
      "observation_identity_ids" => Enum.map(envelopes, & &1.observation_identity_id),
      "validity_state" => envelopes |> List.first() |> Map.get(:validity_state) |> enum_string(),
      "revision" => Keyword.get(opts, :revision, 1),
      "source_endpoint_id" => envelopes |> List.first() |> Map.get(:source_endpoint_id),
      "replay_run_id" => envelopes |> List.first() |> Map.get(:replay_run_id),
      "supersedes_observation_id" => Keyword.get(opts, :supersedes_observation_id)
    }
    |> Map.merge(extra_payload)
  end

  defp source_time_range(envelopes) do
    time_range(envelopes, :generation_time) || time_range(envelopes, :receipt_time) || {nil, nil}
  end

  defp receipt_time_range(envelopes) do
    time_range(envelopes, :receipt_time) || {nil, nil}
  end

  defp time_range(envelopes, field) do
    envelopes
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      times ->
        Enum.min_max_by(times, &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp latest_datetime(datetimes) do
    datetimes
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> DateTime.utc_now() end)
  end

  defp dataset_for_realm(realm) when is_atom(realm), do: Atom.to_string(realm)
  defp dataset_for_realm(realm), do: realm

  defp present?(value), do: is_binary(value) and value != ""

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp storage_config do
    Application.get_env(:cadence, :telemetry_storage, [])
  end

  defp writer_opts do
    storage_config()
    |> Keyword.get(:writer_opts, [])
  end

  defp ensure_writer_loaded!(writer) when is_atom(writer) do
    case Code.ensure_loaded(writer) do
      {:module, ^writer} ->
        writer

      {:error, reason} ->
        raise "could not load telemetry storage writer #{inspect(writer)}: #{inspect(reason)}"
    end
  end
end
