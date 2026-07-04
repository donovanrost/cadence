defmodule CadenceWeb.OpsDashboardShowLive.WidgetSourceStatus do
  @moduledoc """
  Source freshness and availability summary for engine-backed widget data.

  Widget lifecycle answers "how should this widget render"; source status
  answers "what source facts led to that lifecycle".
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames, ResolveWarning}

  @availability_warning_codes [
    :source_execution_failed,
    :source_unavailable,
    :missing_source_binding,
    :missing_data_source,
    :missing_mission_id,
    :missing_organization_id
  ]

  @stale_warning_codes [
    :stale_data,
    :stale_limit_state,
    :missing_snapshot,
    :watermark_unknown,
    :unknown_watermark,
    :source_degraded
  ]

  @partial_warning_codes [
    :partial_data,
    :partial_event_coverage
  ]

  @type t :: %{
          required(:state) => atom(),
          required(:severity) => atom(),
          required(:data_state) => atom(),
          required(:stale?) => boolean(),
          required(:warning_codes) => [atom()],
          required(:watermarks) => [map()]
        }

  @spec summarize(PlacementFrames.t(), Frame.t() | [Frame.t()] | nil, atom(), boolean()) :: t()
  def summarize(%PlacementFrames{} = placement_frames, frames, data_state, stale?) do
    frames = frames |> List.wrap() |> Enum.filter(&match?(%Frame{}, &1))
    warning_codes = warning_codes(placement_frames, frames)
    watermarks = source_watermarks(frames)
    warning_details = placement_warning_details(placement_frames)
    source_facts = watermarks ++ warning_details
    source_contexts = source_request_contexts(frames) ++ source_frame_contexts(frames)
    freshness_states = source_facts |> context_values(:freshness_state) |> Enum.uniq()
    source_health_states = source_contexts |> context_values(:source_health) |> Enum.uniq()
    warning_codes = Enum.uniq(warning_codes ++ source_health_warning_codes(source_health_states))

    state = state(data_state, stale?, warning_codes, freshness_states, source_health_states)
    empty_reason = empty_reason(data_state, source_contexts)

    %{
      state: state,
      severity: severity(state),
      data_state: data_state,
      stale?: stale? or state in [:stale, :retention_gap, :unknown],
      warning_codes: warning_codes,
      watermarks: watermarks
    }
    |> maybe_put(:freshness_states, freshness_states)
    |> maybe_put(:confidences, source_facts |> context_values(:confidence) |> Enum.uniq())
    |> maybe_put(:logical_sources, source_values(source_facts, source_contexts, :logical_source))
    |> maybe_put(
      :source_request_ids,
      source_values(source_facts, source_contexts, :source_request_id)
    )
    |> maybe_put(:realms, source_values(source_facts, source_contexts, :realm))
    |> maybe_put(:data_source_ids, source_values(source_facts, source_contexts, :data_source_id))
    |> maybe_put(
      :source_binding_ids,
      source_values(source_facts, source_contexts, :source_binding_id)
    )
    |> maybe_put(:time_modes, source_values(source_facts, source_contexts, :time_mode))
    |> maybe_put(:time_axes, source_values(source_facts, source_contexts, :time_axis))
    |> maybe_put(:replay_run_ids, source_values(source_facts, source_contexts, :replay_run_id))
    |> maybe_put(:scope_kinds, source_values(source_facts, source_contexts, :scope_kind))
    |> maybe_put(:scope_ids, source_values(source_facts, source_contexts, :scope_ids))
    |> maybe_put(:contact_ids, source_values(source_facts, source_contexts, :contact_id))
    |> maybe_put(
      :source_endpoint_ids,
      source_values(source_facts, source_contexts, :source_endpoint_ids)
    )
    |> maybe_put(:source_health_states, source_health_states)
    |> maybe_put(
      :source_health_reasons,
      source_values(source_facts, source_contexts, :source_health_reason)
    )
    |> maybe_put(
      :source_health_event_ids,
      source_values(source_facts, source_contexts, :source_health_event_id)
    )
    |> maybe_put(:empty_reason, empty_reason)
  end

  defp state(data_state, stale?, warning_codes, freshness_states, source_health_states) do
    source_problem_state(warning_codes, freshness_states, source_health_states, stale?) ||
      data_state(data_state)
  end

  defp source_problem_state(warning_codes, freshness_states, source_health_states, stale?) do
    cond do
      unavailable?(warning_codes, source_health_states) -> :unavailable
      retention_gap?(warning_codes, freshness_states) -> :retention_gap
      degraded_source?(source_health_states) -> :degraded
      partial?(warning_codes) -> :partial
      unknown_source?(warning_codes, freshness_states, source_health_states) -> :unknown
      stale_source?(warning_codes, freshness_states, stale?) -> :stale
      true -> nil
    end
  end

  defp unavailable?(warning_codes, source_health_states),
    do:
      Enum.any?(warning_codes, &(&1 in @availability_warning_codes)) or
        source_health_state?(source_health_states, :unavailable)

  defp retention_gap?(warning_codes, freshness_states),
    do: :retention_gap in warning_codes or :retention_gap in freshness_states

  defp degraded_source?(source_health_states),
    do: source_health_state?(source_health_states, :degraded)

  defp partial?(warning_codes),
    do: Enum.any?(warning_codes, &(&1 in @partial_warning_codes))

  defp stale_source?(warning_codes, freshness_states, stale?),
    do:
      stale? or :stale in freshness_states or
        Enum.any?(warning_codes, &(&1 in @stale_warning_codes))

  defp unknown_source?(warning_codes, freshness_states, source_health_states),
    do:
      :missing_snapshot in warning_codes or :missing in freshness_states or
        :unknown in freshness_states or source_health_state?(source_health_states, :unknown)

  defp source_health_state?(states, expected) do
    Enum.any?(states, &(normalize_code(&1) == expected))
  end

  defp source_health_warning_codes(states) do
    states
    |> Enum.map(&normalize_code/1)
    |> Enum.flat_map(fn
      :unavailable -> [:source_unavailable]
      :degraded -> [:source_degraded]
      :unknown -> [:source_health_unknown]
      _state -> []
    end)
  end

  defp data_state(:no_data), do: :no_data
  defp data_state(_data_state), do: :fresh

  defp severity(:fresh), do: :ok
  defp severity(:no_data), do: :info
  defp severity(:unknown), do: :warning
  defp severity(:degraded), do: :warning
  defp severity(:partial), do: :warning
  defp severity(:stale), do: :warning
  defp severity(:retention_gap), do: :error
  defp severity(:unavailable), do: :error

  defp warning_codes(%PlacementFrames{warnings: warnings}, frames) do
    warnings
    |> placement_warning_codes()
    |> Kernel.++(frame_warning_codes(frames))
    |> Enum.uniq()
  end

  defp placement_warning_codes(warnings) when is_list(warnings) do
    warnings
    |> Enum.map(&warning_code/1)
    |> Enum.reject(&is_nil/1)
  end

  defp placement_warning_codes(_warnings), do: []

  defp warning_code(%ResolveWarning{code: code}), do: normalize_code(code)

  defp warning_code(warning) when is_map(warning),
    do: warning |> context_value(:code) |> normalize_code()

  defp warning_code(_warning), do: nil

  defp placement_warning_details(%PlacementFrames{warnings: warnings}) when is_list(warnings) do
    warnings
    |> Enum.map(&warning_details/1)
    |> Enum.filter(&is_map/1)
    |> Enum.map(&drop_empty_values/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp placement_warning_details(%PlacementFrames{}), do: []

  defp warning_details(%ResolveWarning{details: details}), do: details

  defp warning_details(warning) when is_map(warning),
    do: context_value(warning, :details)

  defp warning_details(_warning), do: nil

  defp frame_warning_codes(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(fn
      %Frame{meta: meta} when is_map(meta) ->
        meta
        |> context_value(:warning_codes)
        |> List.wrap()

      _frame ->
        []
    end)
    |> Enum.map(&normalize_code/1)
    |> Enum.reject(&is_nil/1)
  end

  defp source_watermarks(frames) do
    frames
    |> Enum.flat_map(fn
      %Frame{meta: meta} when is_map(meta) ->
        meta
        |> context_value(:source_watermarks)
        |> List.wrap()
        |> Enum.filter(&is_map/1)

      _frame ->
        []
    end)
    |> Enum.map(&drop_empty_values/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp source_request_contexts(frames) do
    frames
    |> Enum.flat_map(fn
      %Frame{meta: meta} when is_map(meta) ->
        meta
        |> context_value(:source_request_context)
        |> List.wrap()
        |> Enum.filter(&is_map/1)

      _frame ->
        []
    end)
    |> Enum.map(&drop_empty_values/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp source_frame_contexts(frames) do
    frames
    |> Enum.map(fn
      %Frame{meta: meta} when is_map(meta) ->
        %{
          data_source_id: context_value(meta, :data_source_id),
          source_binding_id: context_value(meta, :source_binding_id),
          source_endpoint_ids: context_value(meta, :source_endpoint_ids),
          source_health: context_value(meta, :source_health),
          source_health_reason: context_value(meta, :source_health_reason),
          source_health_event_id: context_value(meta, :source_health_event_id),
          source_health_freshness: context_value(meta, :source_health_freshness)
        }
        |> drop_empty_values()

      _frame ->
        %{}
    end)
    |> Enum.reject(&(&1 == %{}))
  end

  defp source_values(source_facts, source_contexts, key) do
    (context_values(source_facts, watermark_key(key)) ++
       context_values(source_facts, key) ++
       context_values(source_facts, alias_key(key)) ++
       context_values(source_facts, requested_source_fact_key(key)) ++
       context_values(source_contexts, key) ++
       context_values(source_contexts, alias_key(key)) ++
       context_values(source_contexts, requested_key(key)))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp context_values(contexts, key) when is_list(contexts) do
    contexts
    |> Enum.flat_map(fn context ->
      context
      |> context_value(key)
      |> context_value_list()
    end)
    |> Enum.reject(&empty?/1)
  end

  defp context_value_list(values) when is_list(values), do: values
  defp context_value_list(value), do: List.wrap(value)

  defp requested_key(:realm), do: :requested_realm
  defp requested_key(:data_source_id), do: :requested_data_source_id
  defp requested_key(:source_binding_id), do: :requested_source_binding_id
  defp requested_key(:scope_kind), do: :requested_scope_kind
  defp requested_key(:scope_ids), do: :requested_scope_ids
  defp requested_key(:contact_id), do: :requested_contact_id
  defp requested_key(key), do: key

  defp requested_source_fact_key(:scope_kind), do: :requested_scope_kind
  defp requested_source_fact_key(:scope_ids), do: :requested_scope_ids
  defp requested_source_fact_key(:contact_id), do: :requested_contact_id
  defp requested_source_fact_key(_key), do: nil

  defp alias_key(:source_binding_id), do: :binding_id
  defp alias_key(_key), do: nil

  defp watermark_key(:source_request_id), do: :request_id
  defp watermark_key(key), do: key

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp empty_reason(:no_data, source_contexts) do
    scope_kinds = source_values([], source_contexts, :scope_kind)
    contact_ids = source_values([], source_contexts, :contact_id)
    source_endpoint_ids = source_values([], source_contexts, :source_endpoint_ids)

    cond do
      (contact_scope?(scope_kinds) or contact_ids != []) and source_endpoint_ids != [] ->
        :contact_scope_no_data

      source_endpoint_ids != [] ->
        :source_endpoint_scope_no_data

      scope_kinds != [] ->
        :scope_no_data

      true ->
        nil
    end
  end

  defp empty_reason(_data_state, _source_contexts), do: nil

  defp contact_scope?(scope_kinds) do
    Enum.any?(scope_kinds, &(to_string(&1) == "contact"))
  end

  defp drop_empty_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> empty?(value) end)
  end

  defp empty?(nil), do: true
  defp empty?(""), do: true
  defp empty?([]), do: true
  defp empty?(_value), do: false

  defp normalize_code(code) when is_atom(code), do: code

  defp normalize_code(code) when is_binary(code) do
    code
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_code(_code), do: nil
end
