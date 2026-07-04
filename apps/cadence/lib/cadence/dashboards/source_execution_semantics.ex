defmodule Cadence.Dashboards.SourceExecutionSemantics do
  @moduledoc """
  Named source-execution outcome semantics for dashboard resolves.

  The engine records low-level cache entries, planned request ids, warnings,
  and counts. This module turns those artifacts into a stable, documented
  vocabulary that UI diagnostics, tests, and future runtime services can share.
  """

  alias Cadence.Dashboards.{DashboardResolveResult, PlannedSourceRequest, ResolveWarning}
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  @type status ::
          :executed
          | :skipped
          | :cache_hit
          | :cache_miss
          | :cache_stale
          | :cache_disabled
          | :facts_error
          | :source_execution_failed
          | :source_unavailable
          | :source_degraded
          | :unsupported_capability

  @type severity :: :ok | :info | :warning | :error
  @type operator_action ::
          :none
          | :wait_for_refresh
          | :inspect_source_configuration
          | :inspect_source_failure
          | :inspect_source_health
          | :inspect_source_capability
  @type runtime_action ::
          :none
          | :refresh_source_result
          | :retry_source_execution
          | :wait_for_source_health
          | :requires_configuration_change

  @type status_policy :: %{
          required(:severity) => severity(),
          required(:actionable?) => boolean(),
          required(:retryable?) => boolean(),
          required(:dashboard_degraded?) => boolean(),
          required(:operator_action) => operator_action(),
          required(:runtime_action) => runtime_action()
        }

  @type outcome :: %{
          required(:request_id) => binary(),
          required(:logical_source) => atom() | nil,
          required(:status) => status(),
          required(:executed?) => boolean(),
          required(:degraded?) => boolean(),
          required(:severity) => severity(),
          required(:actionable?) => boolean(),
          required(:retryable?) => boolean(),
          required(:dashboard_degraded?) => boolean(),
          required(:operator_action) => operator_action(),
          required(:runtime_action) => runtime_action(),
          required(:cache_status) => atom() | nil,
          required(:warning_codes) => [atom()],
          required(:warning_severities) => [atom()],
          required(:metadata) => map()
        }

  @type summary :: %{
          required(:source_request_count) => non_neg_integer(),
          required(:executed_source_request_count) => non_neg_integer(),
          required(:skipped_source_request_count) => non_neg_integer(),
          required(:actionable_source_request_count) => non_neg_integer(),
          required(:retryable_source_request_count) => non_neg_integer(),
          required(:returned_frame_count) => non_neg_integer(),
          required(:degraded?) => boolean(),
          required(:outcomes) => [outcome()],
          required(:status_counts) => %{optional(status()) => non_neg_integer()},
          required(:severity_counts) => %{optional(severity()) => non_neg_integer()}
        }

  @status_policies %{
    executed: %{
      severity: :ok,
      actionable?: false,
      retryable?: false,
      dashboard_degraded?: false,
      operator_action: :none,
      runtime_action: :none
    },
    skipped: %{
      severity: :info,
      actionable?: false,
      retryable?: false,
      dashboard_degraded?: false,
      operator_action: :none,
      runtime_action: :none
    },
    cache_hit: %{
      severity: :ok,
      actionable?: false,
      retryable?: false,
      dashboard_degraded?: false,
      operator_action: :none,
      runtime_action: :none
    },
    cache_miss: %{
      severity: :info,
      actionable?: false,
      retryable?: false,
      dashboard_degraded?: false,
      operator_action: :none,
      runtime_action: :none
    },
    cache_stale: %{
      severity: :warning,
      actionable?: false,
      retryable?: true,
      dashboard_degraded?: false,
      operator_action: :wait_for_refresh,
      runtime_action: :refresh_source_result
    },
    cache_disabled: %{
      severity: :info,
      actionable?: false,
      retryable?: false,
      dashboard_degraded?: false,
      operator_action: :none,
      runtime_action: :none
    },
    facts_error: %{
      severity: :error,
      actionable?: true,
      retryable?: true,
      dashboard_degraded?: true,
      operator_action: :inspect_source_configuration,
      runtime_action: :retry_source_execution
    },
    source_execution_failed: %{
      severity: :error,
      actionable?: true,
      retryable?: true,
      dashboard_degraded?: true,
      operator_action: :inspect_source_failure,
      runtime_action: :retry_source_execution
    },
    source_unavailable: %{
      severity: :error,
      actionable?: true,
      retryable?: true,
      dashboard_degraded?: true,
      operator_action: :inspect_source_health,
      runtime_action: :wait_for_source_health
    },
    source_degraded: %{
      severity: :warning,
      actionable?: true,
      retryable?: true,
      dashboard_degraded?: true,
      operator_action: :inspect_source_health,
      runtime_action: :wait_for_source_health
    },
    unsupported_capability: %{
      severity: :error,
      actionable?: true,
      retryable?: false,
      dashboard_degraded?: true,
      operator_action: :inspect_source_capability,
      runtime_action: :requires_configuration_change
    }
  }

  @spec summarize(DashboardResolveResult.t()) :: summary()
  def summarize(%DashboardResolveResult{} = result) do
    planned_outcomes = Enum.map(result.planned_source_requests, &outcome(result, &1))
    planned_ids = MapSet.new(Enum.map(planned_outcomes, & &1.request_id))
    outcomes = planned_outcomes ++ warning_only_outcomes(result, planned_ids)

    %{
      source_request_count: metadata_count(result, :source_request_count, length(outcomes)),
      executed_source_request_count: metadata_count(result, :executed_source_request_count, 0),
      skipped_source_request_count: metadata_count(result, :skipped_source_request_count, 0),
      actionable_source_request_count: Enum.count(outcomes, & &1.actionable?),
      retryable_source_request_count: Enum.count(outcomes, & &1.retryable?),
      returned_frame_count: metadata_count(result, :returned_frame_count, 0),
      degraded?: Map.get(result.plan_metadata, :degraded?, degraded?(outcomes)),
      outcomes: outcomes,
      status_counts: Enum.frequencies_by(outcomes, & &1.status),
      severity_counts: Enum.frequencies_by(outcomes, & &1.severity)
    }
  end

  @spec source_capability_posture_events(DashboardResolveResult.t(), keyword() | map()) :: [
          OperationalEvent.t()
        ]
  def source_capability_posture_events(%DashboardResolveResult{} = result, opts \\ []) do
    result
    |> summarize()
    |> Map.fetch!(:outcomes)
    |> Enum.filter(&(get_in(&1, [:metadata, :capability_posture]) not in [nil, %{}]))
    |> Enum.map(&source_capability_posture_event(result, &1, opts))
  end

  @spec status_policy(status()) :: status_policy()
  def status_policy(status) when is_atom(status), do: Map.fetch!(@status_policies, status)

  @spec outcome_for(DashboardResolveResult.t(), binary()) :: outcome() | nil
  def outcome_for(%DashboardResolveResult{} = result, request_id) when is_binary(request_id) do
    result
    |> summarize()
    |> Map.fetch!(:outcomes)
    |> Enum.find(&(&1.request_id == request_id))
  end

  defp outcome(%DashboardResolveResult{} = result, %PlannedSourceRequest{} = request) do
    cache_entry = cache_entry(result, request.request_id)
    warnings = warnings_for_request(result, request.request_id)
    warning_codes = Enum.map(warnings, & &1.code)
    warning_severities = Enum.map(warnings, & &1.severity)
    cache_status = cache_status(cache_entry)
    executed? = executed?(result, request.request_id, cache_status)
    status = status(cache_status, warning_codes, executed?)
    status_policy = status_policy(status)
    degraded? = degraded?(status_policy, warning_severities)
    capability_posture = capability_posture(request, cache_entry)

    %{
      request_id: request.request_id,
      logical_source: request.logical_source,
      status: status,
      executed?: executed?,
      degraded?: degraded?,
      severity: status_policy.severity,
      actionable?: status_policy.actionable?,
      retryable?: status_policy.retryable?,
      dashboard_degraded?: status_policy.dashboard_degraded?,
      operator_action: status_policy.operator_action,
      runtime_action: status_policy.runtime_action,
      cache_status: cache_status,
      warning_codes: warning_codes,
      warning_severities: warning_severities,
      metadata:
        %{
          observables: request.observables,
          organization_id: request.organization_id,
          mission_id: request.mission_id,
          sampling_mode: Map.get(request.sampling, :mode),
          consumers: request.consumers,
          source_binding_id: metadata_value(request, cache_entry, :source_binding_id),
          data_source_id: metadata_value(request, cache_entry, :data_source_id),
          realm: metadata_value(request, cache_entry, :realm),
          dataset: metadata_value(request, cache_entry, :dataset),
          capability_status: capability_posture_status(capability_posture),
          capability_posture: capability_posture,
          source_dependencies: source_dependencies(request),
          cache_reasons: cache_reasons(cache_entry),
          cache_key: cache_key(cache_entry)
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
    }
  end

  defp source_capability_posture_event(result, outcome, opts) do
    metadata = Map.fetch!(outcome, :metadata)
    posture = Map.fetch!(metadata, :capability_posture)

    OperationalEvent.from_source_capability_posture(%{
      organization_id: option(opts, :organization_id) || Map.get(metadata, :organization_id),
      mission_id: option(opts, :mission_id) || Map.get(metadata, :mission_id),
      dashboard_id: option(opts, :dashboard_id) || result.dashboard_id,
      dashboard_version:
        option(opts, :dashboard_version) || plan_metadata(result, :dashboard_version),
      resolve_id: option(opts, :resolve_id) || plan_metadata(result, :resolve_id),
      source_request_id: outcome.request_id,
      logical_source: outcome.logical_source,
      data_source_id: Map.get(metadata, :data_source_id),
      source_binding_id: Map.get(metadata, :source_binding_id),
      realm: Map.get(metadata, :realm),
      dataset: Map.get(metadata, :dataset),
      replay_run_id: option(opts, :replay_run_id) || plan_metadata(result, :replay_run_id),
      observed_at: option(opts, :observed_at) || DateTime.utc_now(),
      status: capability_posture_status(posture),
      capability_posture: posture,
      source_execution_status: outcome.status,
      source_execution_cache_status: outcome.cache_status,
      source_execution_operator_action: outcome.operator_action,
      source_execution_runtime_action: outcome.runtime_action,
      source_execution_warning_codes: outcome.warning_codes,
      metadata: source_capability_posture_event_metadata(result, outcome, opts)
    })
  end

  defp source_capability_posture_event_metadata(result, outcome, opts) do
    %{
      resolve_mode: result.resolve_mode,
      dashboard_degraded?: outcome.dashboard_degraded?,
      actionable?: outcome.actionable?,
      retryable?: outcome.retryable?,
      source_event: :capability_posture,
      source_event_version: 1,
      causation_event_id: option(opts, :causation_event_id)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp status(cache_status, warning_codes, true) do
    cache_failure_status(cache_status) ||
      warning_failure_status(warning_codes) ||
      cache_success_status(cache_status) ||
      :executed
  end

  defp status(_cache_status, warning_codes, false) do
    if :unsupported_source_capability in warning_codes,
      do: :unsupported_capability,
      else: :skipped
  end

  defp cache_failure_status(:source_execution_failed), do: :source_execution_failed
  defp cache_failure_status(:facts_error), do: :facts_error
  defp cache_failure_status(_cache_status), do: nil

  defp warning_failure_status(warning_codes) do
    cond do
      :source_degraded in warning_codes -> :source_degraded
      :source_unavailable in warning_codes -> :source_unavailable
      :unsupported_source_capability in warning_codes -> :unsupported_capability
      true -> nil
    end
  end

  defp cache_success_status(:hit), do: :cache_hit
  defp cache_success_status(:miss), do: :cache_miss
  defp cache_success_status(:stale), do: :cache_stale
  defp cache_success_status(:disabled), do: :cache_disabled
  defp cache_success_status(_cache_status), do: nil

  defp executed?(%DashboardResolveResult{} = result, request_id, cache_status) do
    cond do
      cache_status in [:hit, :miss, :stale, :disabled, :facts_error, :source_execution_failed] ->
        true

      source_request_has_frames?(result, request_id) ->
        true

      true ->
        false
    end
  end

  defp cache_entry(%DashboardResolveResult{} = result, request_id) do
    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> case do
      entries when is_map(entries) -> Map.get(entries, request_id)
      _other -> nil
    end
  end

  defp cache_status(%{status: status}) when is_atom(status), do: status
  defp cache_status(%{"status" => status}) when is_binary(status), do: known_cache_status(status)
  defp cache_status(_entry), do: nil

  defp known_cache_status("hit"), do: :hit
  defp known_cache_status("miss"), do: :miss
  defp known_cache_status("stale"), do: :stale
  defp known_cache_status("disabled"), do: :disabled
  defp known_cache_status("facts_error"), do: :facts_error
  defp known_cache_status("source_execution_failed"), do: :source_execution_failed
  defp known_cache_status(_status), do: nil

  defp cache_reasons(%{reasons: reasons}) when is_list(reasons), do: reasons
  defp cache_reasons(%{"reasons" => reasons}) when is_list(reasons), do: reasons
  defp cache_reasons(%{reason: reason}) when not is_nil(reason), do: [reason]
  defp cache_reasons(%{"reason" => reason}) when not is_nil(reason), do: [reason]
  defp cache_reasons(_entry), do: []

  defp cache_key(%{key: key}), do: key
  defp cache_key(%{"key" => key}), do: key
  defp cache_key(_entry), do: nil

  defp source_dependencies(%PlannedSourceRequest{source_dependencies: dependencies})
       when is_list(dependencies),
       do: dependencies

  defp source_dependencies(%PlannedSourceRequest{}), do: []

  defp warnings_for_request(%DashboardResolveResult{} = result, request_id) do
    result.dashboard_warnings
    |> Enum.filter(fn
      %ResolveWarning{details: %{source_request_id: ^request_id}} -> true
      %ResolveWarning{details: %{"source_request_id" => ^request_id}} -> true
      _warning -> false
    end)
  end

  defp warning_only_outcomes(%DashboardResolveResult{} = result, planned_ids) do
    result.dashboard_warnings
    |> Enum.map(&warning_request_id/1)
    |> Enum.reject(&(is_nil(&1) or MapSet.member?(planned_ids, &1)))
    |> Enum.uniq()
    |> Enum.map(fn request_id ->
      warnings = warnings_for_request(result, request_id)
      warning_codes = Enum.map(warnings, & &1.code)
      warning_severities = Enum.map(warnings, & &1.severity)
      status = status(nil, warning_codes, false)
      status_policy = status_policy(status)

      %{
        request_id: request_id,
        logical_source: warning_logical_source(warnings),
        status: status,
        executed?: false,
        degraded?: degraded?(status_policy, warning_severities),
        severity: status_policy.severity,
        actionable?: status_policy.actionable?,
        retryable?: status_policy.retryable?,
        dashboard_degraded?: status_policy.dashboard_degraded?,
        operator_action: status_policy.operator_action,
        runtime_action: status_policy.runtime_action,
        cache_status: nil,
        warning_codes: warning_codes,
        warning_severities: warning_severities,
        metadata:
          warning_metadata(warnings)
          |> Map.put(:cache_reasons, [])
      }
    end)
  end

  defp warning_request_id(%ResolveWarning{details: %{source_request_id: request_id}})
       when is_binary(request_id),
       do: request_id

  defp warning_request_id(%ResolveWarning{details: %{"source_request_id" => request_id}})
       when is_binary(request_id),
       do: request_id

  defp warning_request_id(_warning), do: nil

  defp warning_logical_source(warnings) do
    warnings
    |> Enum.find_value(fn
      %ResolveWarning{details: %{logical_source: logical_source}} -> logical_source
      %ResolveWarning{details: %{"logical_source" => logical_source}} -> logical_source
      _warning -> nil
    end)
  end

  defp warning_metadata(warnings) do
    warnings
    |> List.first()
    |> case do
      %ResolveWarning{details: details} when is_map(details) ->
        details
        |> Map.take([
          :source_binding_id,
          :binding_id,
          :data_source_id,
          :realm,
          :dataset,
          :requested_sampling,
          :supported_sampling,
          :fallback,
          "source_binding_id",
          "binding_id",
          "data_source_id",
          "realm",
          "dataset",
          "requested_sampling",
          "supported_sampling",
          "fallback"
        ])
        |> normalize_string_keys()

      _other ->
        %{}
    end
  end

  defp normalize_string_keys(map) do
    Map.new(map, fn
      {"source_binding_id", value} ->
        {:source_binding_id, value}

      {"binding_id", value} ->
        {:binding_id, value}

      {"data_source_id", value} ->
        {:data_source_id, value}

      {"realm", value} ->
        {:realm, value}

      {"dataset", value} ->
        {:dataset, value}

      {"requested_sampling", value} ->
        {:requested_sampling, value}

      {"supported_sampling", value} ->
        {:supported_sampling, value}

      {"fallback", value} ->
        {:fallback, value}

      entry ->
        entry
    end)
  end

  defp source_request_has_frames?(%DashboardResolveResult{} = result, request_id) do
    Enum.any?(result.frames_by_placement, fn {_placement_id, placement_frames} ->
      request_id in placement_frames.planned_request_ids and
        (placement_frames.primary != [] or placement_frames.overlays != %{})
    end)
  end

  defp metadata_value(%PlannedSourceRequest{} = request, cache_entry, key) do
    get_in(request.metadata, [:capability_provenance, key]) ||
      get_in(cache_entry || %{}, [key]) ||
      get_in(cache_entry || %{}, [:capability_provenance, key])
  end

  defp capability_posture(%PlannedSourceRequest{} = request, cache_entry) do
    get_in(request.metadata, [:capability_provenance, :capability_posture]) ||
      get_in(cache_entry || %{}, [:capability_posture]) ||
      get_in(cache_entry || %{}, [:capability_provenance, :capability_posture])
  end

  defp capability_posture_status(%{status: status}) when is_atom(status), do: status
  defp capability_posture_status(%{"status" => status}) when is_binary(status), do: status
  defp capability_posture_status(_posture), do: nil

  defp option(opts, key) when is_list(opts), do: Keyword.get(opts, key)

  defp option(opts, key) when is_map(opts),
    do: Map.get(opts, key, Map.get(opts, Atom.to_string(key)))

  defp option(_opts, _key), do: nil

  defp plan_metadata(%DashboardResolveResult{plan_metadata: metadata}, key) when is_map(metadata),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))

  defp plan_metadata(_result, _key), do: nil

  defp metadata_count(%DashboardResolveResult{} = result, key, default) do
    case Map.get(result.plan_metadata, key) do
      value when is_integer(value) and value >= 0 -> value
      _other -> default
    end
  end

  defp degraded?(outcomes), do: Enum.any?(outcomes, & &1.degraded?)

  defp degraded?(status_policy, warning_severities),
    do: status_policy.dashboard_degraded? or Enum.any?(warning_severities, &(&1 == :error))
end
