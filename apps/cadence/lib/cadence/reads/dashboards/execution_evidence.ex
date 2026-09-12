defmodule Cadence.Reads.Dashboards.ExecutionEvidence do
  @moduledoc "Bounded diagnostic metadata projection; never serializes source values or raw provenance."

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    Frame,
    ResolveWarning,
    RuntimeCacheKey,
    SourceExecutionSemantics
  }

  @limit 50
  @inspection_collections ~w(plan requests frames cache source_execution)

  def inspection(%DashboardResolveResult{} = result) do
    true = length(result.planned_source_requests) <= 2048
    true = map_size(result.frames_by_placement) <= 1024
    summary = SourceExecutionSemantics.summarize(result)

    [
      collection(
        "plan",
        "inspection",
        Stream.concat(
          [plan(result, summary)],
          Stream.map(result.dashboard_warnings, &warning(result.dashboard_id, &1))
        )
      ),
      collection(
        "requests",
        "inspection",
        Stream.map(result.planned_source_requests, &request/1)
      ),
      collection("frames", "inspection", frames(result)),
      collection("cache", "inspection", cache(result)),
      collection("source_execution", "inspection", Stream.map(summary.outcomes, &outcome/1))
    ]
  end

  def unavailable_inspection do
    Enum.map(@inspection_collections, &unavailable/1)
  end

  def decisions(rows, source) when source in ["durable", "process_local"] do
    [
      collection("refresh", source, Stream.map(rows, &refresh/1)),
      collection("invalidation", source, Stream.map(rows, &invalidation/1))
    ]
  end

  def unavailable_decisions, do: Enum.map(~w(refresh invalidation), &unavailable/1)

  defp unavailable(id),
    do: %{id: id, state: "unavailable", source: nil, limited: false, rows: []}

  defp collection(id, source, rows) do
    rows = rows |> Stream.uniq_by(& &1.id) |> Enum.take(@limit + 1)

    %{
      id: id,
      state: "ready",
      source: source,
      limited: length(rows) > @limit,
      rows: Enum.take(rows, @limit)
    }
  end

  defp plan(result, summary) do
    row(
      "plan",
      [result.dashboard_id],
      result.dashboard_id,
      "Resolve plan",
      if(summary.degraded? or result.plan_metadata[:degraded?] == true,
        do: "degraded",
        else: "ready"
      ),
      resolve_mode: result.resolve_mode,
      requests: summary.source_request_count,
      executed_requests: summary.executed_source_request_count,
      skipped_requests: summary.skipped_source_request_count,
      returned_frames: summary.returned_frame_count,
      warnings: length(result.dashboard_warnings),
      live_append_eligible: result.plan_metadata[:live_append_eligible?],
      snapshot: result.plan_metadata[:snapshot?]
    )
  end

  defp request(request) do
    row("requests", [request.request_id], request.request_id, "Source request", "planned",
      logical_source: request.logical_source,
      observable_count: length(request.observables),
      observables: names(request.observables),
      consumer_count: length(request.consumers),
      placements: names(Enum.map(request.consumers, & &1.placement_id)),
      time_mode: request.time_context.mode,
      time_axis: request.time_context.axis,
      from: request.time_context.from,
      to: request.time_context.to,
      realm: request.data_context.realm,
      data_view: request.data_context.view,
      limit_mode: request.limit_context.semantics_mode
    )
  end

  # Warning prose, arbitrary details, links and evidence can contain source data.
  # Admit only exact diagnostic identities; never truncate them into another identity.
  defp warning(dashboard, %ResolveWarning{} = warning) do
    true = warning.severity in [:info, :warning, :error]
    true = warning.scope in [:dashboard, :placement, :frame, :field]
    code = warning_name(warning.code)
    true = is_binary(code)

    details = [
      warning_code: code,
      scope: Atom.to_string(warning.scope),
      placement_id: exact_warning_identity(warning.placement_id),
      frame_id: exact_warning_identity(warning.frame_id),
      field_name: exact_warning_identity(warning.field_name),
      source_request_id: exact_warning_identity(warning_detail(warning, :source_request_id)),
      logical_source: warning_name(warning_detail(warning, :logical_source))
    ]

    identity =
      digest([
        dashboard,
        warning.severity,
        Enum.map(details, fn {key, value} -> [key, value] end)
      ])

    row("plan_warning", [identity], identity, code, warning.severity, details)
  end

  defp warning_detail(%ResolveWarning{details: details}, key) do
    Map.get(details, key, Map.get(details, Atom.to_string(key)))
  end

  defp warning_name(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: value |> Atom.to_string() |> exact_warning_identity()

  defp warning_name(value), do: exact_warning_identity(value)

  defp exact_warning_identity(nil), do: nil

  defp exact_warning_identity(value) do
    true = is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)
    false = Regex.match?(~r/[\x00-\x1f\x7f]/u, value)
    value
  end

  defp frames(result) do
    result.frames_by_placement
    |> Enum.sort_by(&elem(&1, 0))
    |> Stream.flat_map(&placement_frames/1)
  end

  defp placement_frames({placement, bucket}) do
    [{:primary, bucket.primary} | Enum.sort_by(bucket.overlays, &elem(&1, 0))]
    |> Stream.flat_map(fn {role, frames} -> role_frames(placement, role, frames) end)
  end

  defp role_frames(placement, role, frames) do
    frames
    |> Stream.with_index()
    |> Stream.map(fn {frame, index} -> frame(placement, role, index, frame) end)
  end

  defp frame(placement, role, index, %Frame{} = frame) do
    identity = frame.frame_id || placement

    row(
      "frames",
      [placement, Atom.to_string(role), Integer.to_string(index), identity],
      identity,
      "Materialized frame",
      "returned",
      placement_id: placement,
      frame_id: frame.frame_id,
      role: role,
      source: frame.source,
      shape: frame.shape,
      time_axis: frame.time_axis,
      field_count: length(frame.fields)
    )
  end

  defp cache(result) do
    metadata = Map.get(result.plan_metadata, :cache, %{})

    plan =
      case metadata[:plan_cache] do
        nil -> []
        entry -> [cache_entry("plan", nil, nil, entry)]
      end

    sources =
      metadata
      |> Map.get(:source_result_cache_by_request_id, %{})
      |> Enum.sort_by(&elem(&1, 0))
      |> Stream.map(fn {request, entry} -> cache_entry("source_result", nil, request, entry) end)

    frames =
      metadata
      |> Map.get(:frame_cache_by_placement, %{})
      |> Enum.sort_by(&elem(&1, 0))
      |> Stream.flat_map(fn {placement, entries} ->
        entries
        |> Enum.sort_by(&elem(&1, 0))
        |> Stream.map(fn {request, entry} -> cache_entry("frame", placement, request, entry) end)
      end)

    Stream.concat([plan, sources, frames])
  end

  defp cache_entry(layer, placement, request, entry) do
    fingerprint =
      case entry[:key] do
        %RuntimeCacheKey{fingerprint: value} -> value
        _ -> nil
      end

    row(
      "cache",
      [layer, placement || "", request || ""],
      fingerprint || layer,
      "Cache observation",
      entry[:status],
      layer: layer,
      placement_id: placement,
      request_id: request,
      fingerprint: fingerprint,
      source_result_status: entry[:source_result_cache_status]
    )
  end

  defp outcome(outcome) do
    row(
      "source_execution",
      [outcome.request_id],
      outcome.request_id,
      "Source execution",
      outcome.status,
      logical_source: outcome.logical_source,
      executed: outcome.executed?,
      degraded: outcome.degraded?,
      severity: outcome.severity,
      actionable: outcome.actionable?,
      retryable: outcome.retryable?,
      cache_status: outcome.cache_status,
      operator_action: outcome.operator_action,
      runtime_action: outcome.runtime_action,
      warning_codes: names(outcome.warning_codes)
    )
  end

  defp refresh(decision) do
    identity = decision_identity(decision)

    row("refresh", [identity], identity, "Recorded refresh decision", decision.refresh_reason,
      observed_at: decision.decision_observed_at,
      refresh_allowed: decision.refresh_allowed?,
      decision_status: decision.decision_status,
      context_reason: decision.context_reason,
      affected_placement_count: decision.affected_placement_count
    )
  end

  defp invalidation(decision) do
    identity = decision_identity(decision)

    row("invalidation", [identity], identity, "Recorded invalidation", decision.decision_status,
      observed_at: decision.decision_observed_at,
      invalidation_event_id: decision.invalidation_event_id,
      boundary: decision.boundary,
      domain_fact: decision.domain_fact,
      matches: decision.matches?,
      context_matches: decision.context_matches?,
      context_reason: decision.context_reason,
      invalidated_artifacts: decision.invalidated_artifacts,
      affected_placement_count: decision.affected_placement_count,
      affected_placements: names(decision.affected_placement_ids || [])
    )
  end

  defp decision_identity(%{dashboard_runtime_invalidation_decision_event_id: id})
       when is_binary(id), do: id

  defp decision_identity(decision) do
    digest([
      decision.invalidation_event_id,
      scalar(decision.decision_observed_at),
      scalar(decision.decision_status)
    ])
  end

  defp row(category, key, identity, title, status, details) do
    true = is_binary(identity) and byte_size(identity) in 1..256 and String.valid?(identity)
    false = Regex.match?(~r/[\x00-\x1f\x7f]/u, identity)

    %{
      kind: category,
      id: digest([category | key]),
      identity: scalar(identity),
      title: title,
      status: scalar(status) || "unknown",
      details:
        Enum.map(details, fn {key, value} -> %{key: Atom.to_string(key), value: scalar(value)} end)
    }
  end

  defp digest(value),
    do: :crypto.hash(:sha256, Jason.encode!(value)) |> Base.encode16(case: :lower)

  defp names(values),
    do:
      values
      |> Enum.take(12)
      |> Enum.map(&scalar/1)
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" · ")

  defp scalar(nil), do: nil
  defp scalar(value) when is_boolean(value), do: value
  defp scalar(value) when is_integer(value) and abs(value) <= 9_007_199_254_740_991, do: value
  defp scalar(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp scalar(value) when is_atom(value), do: value |> Atom.to_string() |> scalar()

  defp scalar(value) when is_binary(value) do
    value
    |> binary_part(0, min(byte_size(value), 256))
    |> valid_prefix()
    |> String.replace(~r/[\x00-\x1f\x7f]/u, " ")
  end

  defp scalar(_), do: nil

  defp valid_prefix(value) do
    if String.valid?(value),
      do: value,
      else: valid_prefix(binary_part(value, 0, byte_size(value) - 1))
  end
end
