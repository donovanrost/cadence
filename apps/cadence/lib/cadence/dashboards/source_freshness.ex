defmodule Cadence.Dashboards.SourceFreshness do
  @moduledoc """
  Engine-owned freshness policy evaluation for source watermarks.

  Source adapters report raw watermark facts. The dashboard engine interprets
  those facts against dashboard/request policy so callers do not encode stale
  semantics in LiveViews or individual widgets.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ResolveWarning, SourceActions, SourceWatermark}

  @type state :: :fresh | :stale | :unknown | :retention_gap

  @spec resolve_policy([map() | nil]) :: map()
  def resolve_policy(policies) when is_list(policies) do
    policies
    |> Enum.map(&normalize_policy/1)
    |> Enum.reject(&(&1 == %{}))
    |> Enum.reduce(%{}, &merge_policy/2)
  end

  @spec annotate(SourceWatermark.t(), PlannedSourceRequest.t(), map(), DateTime.t()) ::
          SourceWatermark.t()
  def annotate(
        %SourceWatermark{} = watermark,
        %PlannedSourceRequest{} = request,
        policy,
        %DateTime{} = now
      ) do
    policy = normalize_policy(policy)

    %SourceWatermark{
      watermark
      | freshness_state: classify(watermark, request, policy, now),
        freshness_policy: policy,
        freshness_checked_at: now
    }
  end

  @spec warning(SourceWatermark.t()) :: ResolveWarning.t() | nil
  def warning(%SourceWatermark{freshness_state: :stale} = watermark) do
    warning(watermark, nil)
  end

  def warning(%SourceWatermark{freshness_state: :retention_gap} = watermark) do
    warning(watermark, nil)
  end

  def warning(%SourceWatermark{}), do: nil

  @spec warning(SourceWatermark.t(), PlannedSourceRequest.t() | nil) :: ResolveWarning.t() | nil
  def warning(%SourceWatermark{freshness_state: :stale} = watermark, request) do
    %ResolveWarning{
      code: :stale_data,
      severity: :warning,
      scope: :dashboard,
      message: "Source watermark is older than freshness policy",
      details:
        watermark
        |> warning_details(request)
        |> SourceActions.put_source_warning_actions()
    }
  end

  def warning(%SourceWatermark{freshness_state: :retention_gap} = watermark, request) do
    %ResolveWarning{
      code: :retention_gap,
      severity: :warning,
      scope: :dashboard,
      message: "Requested time range begins before source retention",
      details:
        watermark
        |> warning_details(request)
        |> SourceActions.put_source_warning_actions()
    }
  end

  def warning(%SourceWatermark{}, _request), do: nil

  defp classify(%SourceWatermark{} = watermark, %PlannedSourceRequest{} = request, policy, now) do
    cond do
      retention_gap?(watermark, request) ->
        :retention_gap

      watermark.confidence == :unknown ->
        :unknown

      is_nil(freshness_cursor(watermark)) ->
        :unknown

      stale?(watermark, request, policy, now) ->
        :stale

      true ->
        :fresh
    end
  end

  defp stale?(%SourceWatermark{} = watermark, %PlannedSourceRequest{} = request, policy, now) do
    case Map.get(policy, :stale_after_ms) do
      stale_after_ms when is_integer(stale_after_ms) and stale_after_ms >= 0 ->
        reference_time = reference_time(request, now)
        DateTime.diff(reference_time, freshness_cursor(watermark), :millisecond) > stale_after_ms

      _other ->
        false
    end
  end

  defp retention_gap?(%SourceWatermark{retention_starts_at: nil}, %PlannedSourceRequest{}),
    do: false

  defp retention_gap?(
         %SourceWatermark{retention_starts_at: %DateTime{} = retention_starts_at},
         request
       ) do
    case requested_start_time(request) do
      %DateTime{} = requested_start ->
        DateTime.compare(requested_start, retention_starts_at) == :lt

      _other ->
        false
    end
  end

  defp freshness_cursor(%SourceWatermark{complete_through: %DateTime{} = time}), do: time
  defp freshness_cursor(%SourceWatermark{latest_receipt_time: %DateTime{} = time}), do: time
  defp freshness_cursor(%SourceWatermark{}), do: nil

  defp reference_time(%PlannedSourceRequest{} = request, now) do
    if time_mode(request) in [:archive, :range] do
      requested_end_time(request) || now
    else
      now
    end
  end

  defp requested_start_time(%PlannedSourceRequest{time_context: time_context}) do
    first_datetime([
      get_attr(time_context, :from),
      get_attr(time_context, :start),
      get_attr(time_context, :start_time)
    ])
  end

  defp requested_end_time(%PlannedSourceRequest{time_context: time_context}) do
    first_datetime([
      get_attr(time_context, :to),
      get_attr(time_context, :end),
      get_attr(time_context, :end_time)
    ])
  end

  defp first_datetime(values) do
    Enum.find_value(values, &normalize_datetime/1)
  end

  defp normalize_datetime(%DateTime{} = value), do: value

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp time_mode(%PlannedSourceRequest{time_context: time_context}) do
    case get_attr(time_context, :mode) do
      "archive" -> :archive
      "range" -> :range
      "live" -> :live
      "replay_run" -> :replay_run
      mode -> mode
    end
  end

  defp warning_details(%SourceWatermark{} = watermark, request) do
    %{
      logical_source: watermark.logical_source,
      source_request_id: watermark.request_id,
      source_binding_id: watermark.source_binding_id,
      data_source_id: watermark.data_source_id,
      realm: watermark.realm,
      dataset: watermark.dataset,
      confidence: watermark.confidence,
      freshness_state: watermark.freshness_state,
      freshness_policy: watermark.freshness_policy,
      freshness_checked_at: watermark.freshness_checked_at,
      complete_through: watermark.complete_through,
      latest_receipt_time: watermark.latest_receipt_time,
      retention_starts_at: watermark.retention_starts_at
    }
    |> SourceActions.put_source_request_context(request, watermark.logical_source)
    |> drop_nil_values()
  end

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp normalize_policy(nil), do: %{}

  defp normalize_policy(policy) when is_map(policy) do
    policy
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_policy_key(key) do
        nil -> acc
        normalized_key -> Map.put(acc, normalized_key, value)
      end
    end)
    |> normalize_stale_after()
  end

  defp normalize_policy(_policy), do: %{}

  defp normalize_policy_key(key) when key in [:stale_after_ms, :stale_after], do: :stale_after_ms
  defp normalize_policy_key("stale_after_ms"), do: :stale_after_ms
  defp normalize_policy_key("stale_after"), do: :stale_after_ms
  defp normalize_policy_key(_key), do: nil

  defp normalize_stale_after(%{stale_after_ms: value} = policy) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> %{policy | stale_after_ms: integer}
      _error -> Map.delete(policy, :stale_after_ms)
    end
  end

  defp normalize_stale_after(%{stale_after_ms: value} = policy) when is_integer(value),
    do: policy

  defp normalize_stale_after(%{stale_after_ms: _value} = policy),
    do: Map.delete(policy, :stale_after_ms)

  defp normalize_stale_after(policy), do: policy

  defp merge_policy(policy, acc) do
    Map.merge(acc, policy, fn
      :stale_after_ms, left, right when is_integer(left) and is_integer(right) -> min(left, right)
      _key, _left, right -> right
    end)
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    Map.get(Map.from_struct(attrs), key)
  end

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp get_attr(_attrs, _key), do: nil
end
