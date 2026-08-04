defmodule Cadence.Dashboards.SourceRegistry.OperationalIntervalProvenance do
  @moduledoc """
  Selects effective operational intervals and shapes source-result provenance.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ScopeContext,
    SourceResult
  }

  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Reads.OperationalEvidence

  @spec build(PlannedSourceRequest.t(), ResolvedSourceBinding.t(), keyword(), SourceResult.t()) ::
          map()
  def build(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        opts,
        %SourceResult{} = result
      ) do
    with true <- Keyword.get(opts, :persisted?, false) == true,
         %DateTime{} = at <-
           selected_operational_interval_at(request, resolved_binding, opts, result),
         mission_id when is_binary(mission_id) <- request.mission_id do
      organization_id = request.organization_id

      intervals =
        [
          selected_binding_set_interval(organization_id, mission_id, at, opts),
          selected_application_binding_interval(
            organization_id,
            mission_id,
            request,
            at,
            opts,
            result
          ),
          selected_catalog_revision_interval(organization_id, mission_id, request, at, opts)
        ]
        |> Enum.reject(&is_nil/1)

      case intervals do
        [] ->
          %{}

        intervals ->
          %{
            selected_operational_interval_at: at,
            selected_operational_intervals: Enum.map(intervals, &EffectiveInterval.metadata/1)
          }
      end
    else
      _other -> %{}
    end
  end

  defp selected_operational_interval_at(
         %PlannedSourceRequest{},
         %ResolvedSourceBinding{segment_from: %DateTime{} = from},
         _opts,
         _result
       ),
       do: from

  defp selected_operational_interval_at(
         %PlannedSourceRequest{},
         _resolved_binding,
         opts,
         %SourceResult{} = result
       ) do
    case Keyword.get(opts, :operational_interval_at) || Keyword.get(opts, :source_binding_at) do
      %DateTime{} = at -> at
      _other -> source_result_interval_at(result)
    end
  end

  defp source_result_interval_at(%SourceResult{frames: frames}) when is_list(frames) do
    Enum.find_value(frames, &frame_interval_at/1)
  end

  defp source_result_interval_at(_result), do: nil

  defp frame_interval_at(%Frame{fields: fields}) when is_list(fields) do
    fields
    |> Enum.sort_by(&frame_interval_field_sort_key/1)
    |> Enum.find_value(fn
      %Field{values: values} when is_list(values) ->
        Enum.find(values, &match?(%DateTime{}, &1))

      _field ->
        nil
    end)
  end

  defp frame_interval_at(_frame), do: nil

  defp frame_interval_field_sort_key(%Field{name: name}) when name in ["time", :time], do: 0

  defp frame_interval_field_sort_key(%Field{name: name})
       when name in ["observed_at", :observed_at], do: 1

  defp frame_interval_field_sort_key(%Field{name: name})
       when name in ["receipt_time", :receipt_time], do: 2

  defp frame_interval_field_sort_key(%Field{name: name})
       when name in ["generation_time", :generation_time], do: 3

  defp frame_interval_field_sort_key(_field), do: 10

  defp selected_binding_set_interval(organization_id, mission_id, %DateTime{} = at, opts) do
    organization_id
    |> list(:binding_set, mission_id, [at: at], opts)
    |> unique()
  end

  defp selected_application_binding_interval(
         organization_id,
         mission_id,
         %PlannedSourceRequest{} = request,
         %DateTime{} = at,
         opts,
         %SourceResult{} = result
       ) do
    case source_endpoint_scope_id(request) || source_endpoint_result_id(result) do
      nil ->
        nil

      source_endpoint_ref ->
        organization_id
        |> list(
          :application_binding,
          mission_id,
          [at: at, source_endpoint_ref: source_endpoint_ref],
          opts
        )
        |> unique()
    end
  end

  defp selected_catalog_revision_interval(
         organization_id,
         mission_id,
         %PlannedSourceRequest{} = request,
         %DateTime{} = at,
         opts
       ) do
    case catalog_family_for_request(request) do
      nil ->
        nil

      catalog_family ->
        organization_id
        |> list(
          :catalog_revision,
          mission_id,
          [at: at, catalog_family: catalog_family],
          opts
        )
        |> unique()
    end
  end

  def list(organization_id, kind, mission_id, interval_opts, registry_opts) do
    case operational_interval_reader(kind, registry_opts) do
      fun when is_function(fun, 3) ->
        fun.(organization_id, mission_id, interval_opts)

      nil ->
        default_operational_intervals(organization_id, kind, mission_id, interval_opts)
    end
  end

  defp default_operational_intervals(organization_id, :binding_set, mission_id, opts) do
    OperationalEvidence.list_effective_intervals(
      :binding_set,
      organization_id,
      mission_id,
      opts
    )
  end

  defp default_operational_intervals(organization_id, :application_binding, mission_id, opts) do
    OperationalEvidence.list_effective_intervals(
      :application_binding,
      organization_id,
      mission_id,
      opts
    )
  end

  defp default_operational_intervals(organization_id, :catalog_revision, mission_id, opts) do
    OperationalEvidence.list_effective_intervals(
      :catalog_revision,
      organization_id,
      mission_id,
      opts
    )
  end

  defp default_operational_intervals(organization_id, :source_health, mission_id, opts) do
    OperationalEvidence.list_effective_intervals(
      :source_health,
      organization_id,
      mission_id,
      opts
    )
  end

  defp operational_interval_reader(:binding_set, opts) do
    Keyword.get(opts, :binding_set_intervals_fun) ||
      operational_interval_reader_from_map(opts, :binding_set)
  end

  defp operational_interval_reader(:application_binding, opts) do
    Keyword.get(opts, :application_binding_intervals_fun) ||
      operational_interval_reader_from_map(opts, :application_binding)
  end

  defp operational_interval_reader(:catalog_revision, opts) do
    Keyword.get(opts, :catalog_revision_intervals_fun) ||
      operational_interval_reader_from_map(opts, :catalog_revision)
  end

  defp operational_interval_reader(:source_health, opts) do
    Keyword.get(opts, :source_health_intervals_fun) ||
      operational_interval_reader_from_map(opts, :source_health)
  end

  defp operational_interval_reader_from_map(opts, kind) do
    case Keyword.get(opts, :operational_interval_funs) do
      funs when is_map(funs) -> Map.get(funs, kind) || Map.get(funs, Atom.to_string(kind))
      funs when is_list(funs) -> Keyword.get(funs, kind)
      _other -> nil
    end
  end

  def unique([%EffectiveInterval{} = interval]), do: interval
  def unique(_intervals), do: nil

  defp catalog_family_for_request(%PlannedSourceRequest{logical_source: logical_source})
       when logical_source in [:telemetry, :limits],
       do: :telemetry

  defp catalog_family_for_request(%PlannedSourceRequest{}), do: nil

  def evidence_refs(interval_provenance, %PlannedSourceRequest{} = request) do
    interval_provenance
    |> Map.get(:selected_operational_intervals, [])
    |> DataLinks.operational_interval_evidence_refs(source: request.logical_source)
  end

  defp source_endpoint_scope_id(%PlannedSourceRequest{scope_context: scope_context}) do
    ScopeContext.scope_id(scope_context, :source_endpoint)
  end

  defp source_endpoint_result_id(%SourceResult{frames: frames}) when is_list(frames) do
    Enum.find_value(frames, fn
      %Frame{meta: meta} ->
        non_empty_text(
          get_attr(meta, :source_endpoint_id) || get_attr(meta, :source_endpoint_ref)
        ) || source_endpoint_frame_field_id(frames)

      _frame ->
        nil
    end)
  end

  defp source_endpoint_result_id(%SourceResult{}), do: nil

  defp source_endpoint_frame_field_id(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(&source_endpoint_frame_field_values/1)
    |> Enum.map(&non_empty_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [source_endpoint_id] -> source_endpoint_id
      _other -> nil
    end
  end

  defp source_endpoint_frame_field_values(%Frame{fields: fields}) when is_list(fields) do
    fields
    |> Enum.filter(fn
      %Field{name: name} -> name in ["source_endpoint_id", "source_endpoint_ref"]
      _field -> false
    end)
    |> Enum.flat_map(fn %Field{values: values} -> List.wrap(values) end)
  end

  defp source_endpoint_frame_field_values(_frame), do: []

  defp non_empty_text(value) when is_binary(value) and value != "", do: value
  defp non_empty_text(_value), do: nil

  @spec reader_configured?(atom(), keyword()) :: boolean()
  def reader_configured?(kind, opts) when is_atom(kind) and is_list(opts) do
    is_function(operational_interval_reader(kind, opts), 3)
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
