defmodule Cadence.Dashboards.FrameLifecycle do
  @moduledoc """
  Shared lifecycle vocabulary for dashboard frame/widget presentation.

  Source adapters and the engine already expose warnings, watermarks, cache
  status, and frame metadata. This module maps those low-level signals into the
  small set of lifecycle states widgets can render consistently.
  """

  alias Cadence.Dashboards.ResolveWarning

  @states [:ready, :no_data, :stale, :partial, :retention_gap, :error, :unsupported]
  @severities %{
    ready: :ok,
    no_data: :info,
    stale: :warning,
    partial: :warning,
    retention_gap: :error,
    error: :error,
    unsupported: :error
  }

  @unsupported_codes [
    :unsupported_widget_frame_contract,
    :unsupported_source_capability,
    :unsupported_source_adapter,
    :unsupported_logical_source,
    :unsupported_sampling,
    :unsupported_time_axis,
    :unsupported_event_family,
    :unsupported_operational_observable,
    :unsupported_operational_observable_backing,
    :unsupported_observable_scope,
    :source_binding_segment_merge_unsupported
  ]

  @error_codes [
    :source_execution_failed,
    :source_unavailable,
    :missing_source_binding,
    :missing_data_source,
    :missing_mission_id,
    :missing_organization_id
  ]

  @retention_gap_codes [:retention_gap]

  @partial_codes [
    :partial_data,
    :partial_event_coverage,
    :corrected_range,
    :advisory_backfill,
    :late_arrival
  ]

  @stale_codes [
    :stale_data,
    :stale_limit_state,
    :missing_snapshot,
    :watermark_unknown,
    :unknown_watermark,
    :source_degraded
  ]

  @type state :: :ready | :no_data | :stale | :partial | :retention_gap | :error | :unsupported
  @type severity :: :ok | :info | :warning | :error
  @type t :: %{
          required(:state) => state(),
          required(:severity) => severity(),
          required(:reason_codes) => [atom()],
          required(:warning_codes) => [atom()]
        }

  @spec states() :: [state()]
  def states, do: @states

  @spec classify(map() | keyword()) :: t()
  def classify(signals) when is_list(signals), do: signals |> Map.new() |> classify()

  def classify(signals) when is_map(signals) do
    warning_codes =
      signals
      |> attr(:warning_codes, [])
      |> List.wrap()
      |> Enum.map(&normalize_code/1)
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(warning_codes(attr(signals, :warnings, [])))
      |> Enum.uniq()

    warning_severities =
      signals
      |> attr(:warning_severities, [])
      |> List.wrap()
      |> Enum.map(&normalize_code/1)
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(warning_severities(attr(signals, :warnings, [])))
      |> Enum.uniq()

    data_state = normalize_code(attr(signals, :data_state))
    stale? = attr(signals, :stale?, false) == true

    state = lifecycle_state(warning_codes, warning_severities, data_state, stale?)

    %{
      state: state,
      severity: Map.fetch!(@severities, state),
      reason_codes: reason_codes(state, warning_codes, data_state, stale?),
      warning_codes: warning_codes
    }
  end

  def classify(_signals), do: classify(%{})

  defp lifecycle_state(warning_codes, warning_severities, data_state, stale?) do
    [
      {intersects?(warning_codes, @unsupported_codes), :unsupported},
      {intersects?(warning_codes, @error_codes) or :error in warning_severities, :error},
      {intersects?(warning_codes, @retention_gap_codes), :retention_gap},
      {data_state == :no_data, :no_data},
      {intersects?(warning_codes, @partial_codes), :partial},
      {stale? or intersects?(warning_codes, @stale_codes), :stale}
    ]
    |> Enum.find_value(:ready, fn
      {true, state} -> state
      {false, _state} -> nil
    end)
  end

  @spec state(t() | map() | nil) :: state()
  def state(%{state: state}) when state in @states, do: state
  def state(_lifecycle), do: :ready

  defp warning_codes(warnings) when is_list(warnings) do
    warnings
    |> Enum.map(&warning_attr(&1, :code))
    |> Enum.map(&normalize_code/1)
    |> Enum.reject(&is_nil/1)
  end

  defp warning_codes(_warnings), do: []

  defp warning_severities(warnings) when is_list(warnings) do
    warnings
    |> Enum.map(&warning_attr(&1, :severity))
    |> Enum.map(&normalize_code/1)
    |> Enum.reject(&is_nil/1)
  end

  defp warning_severities(_warnings), do: []

  defp warning_attr(%ResolveWarning{} = warning, key), do: Map.get(warning, key)
  defp warning_attr(warning, key) when is_map(warning), do: attr(warning, key)
  defp warning_attr(_warning, _key), do: nil

  defp reason_codes(:ready, [], _data_state, false), do: []

  defp reason_codes(state, warning_codes, data_state, stale?) do
    ([state, reason_data_state(data_state), if(stale?, do: :stale)] ++ warning_codes)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp reason_data_state(:ready), do: nil
  defp reason_data_state(data_state), do: data_state

  defp intersects?(left, right), do: Enum.any?(left, &(&1 in right))

  defp normalize_code(value) when is_atom(value), do: value

  defp normalize_code(value) when is_binary(value) do
    value
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_code(_value), do: nil

  defp attr(value, key, default \\ nil)

  defp attr(value, key, default) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key), default))
  end

  defp attr(_value, _key, default), do: default
end
