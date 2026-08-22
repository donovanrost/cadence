defmodule Cadence.Dashboards.SourceResultPreflight do
  @moduledoc """
  Freshness preflight for cached dashboard source results.

  This module does not read or write the runtime cache. It answers the narrower
  question the engine must resolve before it can consume a cached source result:
  does the cached source-result key still match the current source facts?
  """

  alias Cadence.Dashboards.{RuntimeCacheKey, SourceResult}

  @type status :: :usable | :stale
  @type reason ::
          :request_changed
          | :cache_policy_changed
          | :binding_changed
          | :data_source_changed
          | :freshness_policy_changed
          | :watermark_moved
          | :watermark_unknown
          | :freshness_unknown
          | :freshness_stale
          | :retention_gap
          | :data_revision_changed
          | :correction_cursor_changed
          | :backfill_cursor_changed
          | :source_degraded

  @type t :: %__MODULE__{
          status: status(),
          reasons: [reason()],
          details: map()
        }

  defstruct status: :usable, reasons: [], details: %{}

  @spec evaluate(RuntimeCacheKey.t(), SourceResult.t(), RuntimeCacheKey.t(), keyword()) :: t()
  def evaluate(
        %RuntimeCacheKey{layer: :source_result} = cached_key,
        %SourceResult{} = cached_result,
        %RuntimeCacheKey{layer: :source_result} = current_key,
        opts \\ []
      )
      when is_list(opts) do
    cache_policy = cache_policy(cached_key, current_key)

    checks = [
      compare(:cache_policy_changed, cached_key, current_key, [:cache_policy]),
      compare(:request_changed, cached_key, current_key, [:request]),
      compare(:binding_changed, cached_key, current_key, [:source_binding]),
      compare(:binding_changed, cached_key, current_key, [:source_binding_segments]),
      compare(:data_source_changed, cached_key, current_key, [:data_source]),
      compare(:data_revision_changed, cached_key, current_key, [:data_revision]),
      compare(:correction_cursor_changed, cached_key, current_key, [:correction_cursor]),
      compare(:backfill_cursor_changed, cached_key, current_key, [:backfill_cursor])
      | live_freshness_checks(cache_policy, cached_key, cached_result, current_key, opts)
    ]

    reasons =
      checks
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %__MODULE__{
      status: status(reasons),
      reasons: reasons,
      details: details(cached_key, current_key, cached_result, opts)
    }
  end

  @spec usable?(RuntimeCacheKey.t(), SourceResult.t(), RuntimeCacheKey.t(), keyword()) ::
          boolean()
  def usable?(
        %RuntimeCacheKey{} = cached_key,
        %SourceResult{} = result,
        %RuntimeCacheKey{} = current_key,
        opts \\ []
      ) do
    evaluate(cached_key, result, current_key, opts).status == :usable
  end

  defp compare(reason, %RuntimeCacheKey{} = cached_key, %RuntimeCacheKey{} = current_key, path) do
    if get_in(cached_key.parts, path) == get_in(current_key.parts, path) do
      nil
    else
      reason
    end
  end

  defp cache_policy(%RuntimeCacheKey{} = cached_key, %RuntimeCacheKey{} = current_key) do
    case {get_in(cached_key.parts, [:cache_policy]), get_in(current_key.parts, [:cache_policy])} do
      {:snapshot, :snapshot} -> :snapshot
      _other -> :live
    end
  end

  defp live_freshness_checks(:snapshot, _cached_key, _cached_result, _current_key, _opts), do: []

  defp live_freshness_checks(:live, cached_key, cached_result, current_key, opts) do
    [
      compare(:freshness_policy_changed, cached_key, current_key, [:freshness_policy]),
      compare(:watermark_moved, cached_key, current_key, [:watermark_cursor]),
      current_watermark_reason(current_key),
      cached_result_reason(cached_result, current_key),
      source_health_reason(Keyword.get(opts, :source_health, :healthy))
    ]
  end

  defp current_watermark_reason(%RuntimeCacheKey{} = current_key) do
    case get_in(current_key.parts, [:watermark_cursor]) do
      nil ->
        if revision_cursor?(current_key), do: nil, else: :watermark_unknown

      watermark ->
        watermark_reason(watermark)
    end
  end

  defp watermark_reason(watermark) when is_map(watermark) do
    case {watermark_attr(watermark, :confidence), watermark_attr(watermark, :freshness_state)} do
      {:unknown, _state} -> :freshness_unknown
      {_confidence, :unknown} -> :freshness_unknown
      {_confidence, :stale} -> :freshness_stale
      {_confidence, :retention_gap} -> :retention_gap
      {_confidence, _state} -> nil
    end
  end

  defp watermark_attr(watermark, key) do
    Map.get(watermark, key, Map.get(watermark, Atom.to_string(key)))
  end

  defp cached_result_reason(%SourceResult{watermarks: []}, %RuntimeCacheKey{} = current_key) do
    if revision_cursor?(current_key), do: nil, else: :watermark_unknown
  end

  defp cached_result_reason(%SourceResult{watermarks: watermarks}, %RuntimeCacheKey{}) do
    cond do
      Enum.any?(watermarks, &(&1.confidence == :unknown)) ->
        :freshness_unknown

      Enum.any?(watermarks, &(&1.freshness_state == :unknown)) ->
        :freshness_unknown

      Enum.any?(watermarks, &(&1.freshness_state == :stale)) ->
        :freshness_stale

      Enum.any?(watermarks, &(&1.freshness_state == :retention_gap)) ->
        :retention_gap

      true ->
        nil
    end
  end

  defp revision_cursor?(%RuntimeCacheKey{} = key) do
    Enum.any?([:data_revision, :correction_cursor, :backfill_cursor], fn cursor ->
      key.parts
      |> Map.get(cursor)
      |> cursor_present?()
    end)
  end

  defp cursor_present?(value), do: value not in [nil, "", []]

  defp source_health_reason(health) when health in [:healthy, "healthy", nil], do: nil
  defp source_health_reason(_health), do: :source_degraded

  defp status([]), do: :usable
  defp status(_reasons), do: :stale

  defp details(
         %RuntimeCacheKey{} = cached_key,
         %RuntimeCacheKey{} = current_key,
         %SourceResult{} = result,
         opts
       ) do
    %{
      cached_fingerprint: cached_key.fingerprint,
      current_fingerprint: current_key.fingerprint,
      request_id: get_in(current_key.parts, [:request, :request_id]) || result.request_id,
      logical_source: get_in(current_key.parts, [:request, :logical_source]),
      cache_policy: get_in(current_key.parts, [:cache_policy]),
      data_source_id: get_in(current_key.parts, [:data_source, :data_source_id]),
      source_binding_id: get_in(current_key.parts, [:source_binding, :binding_id]),
      source_binding_segments: get_in(current_key.parts, [:source_binding_segments]),
      source_health: Keyword.get(opts, :source_health, :healthy)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
