defmodule Cadence.Dashboards.Sources.Telemetry.FrameContext do
  @moduledoc false

  alias Cadence.Dashboards.{DataContext, PlannedSourceRequest}
  alias Cadence.Telemetry.SelectionPolicy

  @default_limit 10_000

  @spec source_filter_context(keyword()) :: map()
  def source_filter_context(opts) when is_list(opts) do
    %{}
    |> maybe_put_context(:time_axis, Keyword.get(opts, :time_axis))
    |> maybe_put_context(
      :source_endpoint_ids,
      opts
      |> Keyword.get(:source_endpoint_ids)
      |> normalize_source_endpoint_ids()
    )
  end

  @spec data_view(PlannedSourceRequest.t()) :: atom()
  def data_view(%PlannedSourceRequest{} = request) do
    view =
      DataContext.source_value(request.data_context, request.logical_source, :view) ||
        first_context_value(request.data_context, [
          :selection_view,
          :view,
          :data_view,
          :data_management_view
        ])

    SelectionPolicy.view(selection_view: view)
  end

  @spec analysis_basis(PlannedSourceRequest.t()) :: :recomputed_analysis | :observed_fact
  def analysis_basis(%PlannedSourceRequest{} = request) do
    case data_view(request) do
      :recomputed -> :recomputed_analysis
      _observed_view -> :observed_fact
    end
  end

  @spec source_binding_id(map() | nil) :: binary() | nil
  def source_binding_id(%{binding: %{binding_id: binding_id}}), do: binding_id
  def source_binding_id(_source_binding), do: nil

  @spec data_source_id(PlannedSourceRequest.t(), map() | nil) :: binary() | nil
  def data_source_id(_request, %{data_source: %{data_source_id: data_source_id}}),
    do: data_source_id

  def data_source_id(request, _source_binding),
    do: context_value(request.data_context, :data_source_id)

  @spec dataset(map() | nil) :: binary() | nil
  def dataset(%{dataset: dataset}), do: dataset
  def dataset(_source_binding), do: nil

  @spec realm(PlannedSourceRequest.t(), map() | nil) :: atom() | binary()
  def realm(_request, %{realm: realm}), do: realm
  def realm(request, _source_binding), do: context_value(request.data_context, :realm) || :flight

  @spec replay_run_id(PlannedSourceRequest.t()) :: binary() | nil
  def replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      context_value(request.time_context, :replay_run_id)
  end

  @spec sampling_mode(PlannedSourceRequest.t()) :: atom() | binary() | nil
  def sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> context_value(:mode)
    |> normalize_atom()
  end

  @spec time_axis(PlannedSourceRequest.t()) :: atom() | binary() | nil
  def time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:axis)
    |> normalize_atom()
  end

  @spec value_type(PlannedSourceRequest.t()) :: :raw | :engineering
  def value_type(%PlannedSourceRequest{value_type: value_type}) do
    case normalize_atom(value_type) do
      :raw -> :raw
      _other -> :engineering
    end
  end

  @spec raw_point_limit(PlannedSourceRequest.t()) :: pos_integer()
  def raw_point_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :max_raw_points) || context_value(sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_limit)
      _invalid -> @default_limit
    end
  end

  @spec target_points(PlannedSourceRequest.t()) :: pos_integer() | nil
  def target_points(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :target_points) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> nil
    end
  end

  @spec bucket_width_ms(PlannedSourceRequest.t()) :: pos_integer() | nil
  def bucket_width_ms(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :bucket_width_ms) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> nil
    end
  end

  defp first_context_value(context, keys) do
    Enum.find_value(keys, &context_value(context, &1))
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp normalize_source_endpoint_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp normalize_source_endpoint_ids(id) when is_binary(id) and id != "", do: [id]
  defp normalize_source_endpoint_ids(_ids), do: []

  defp maybe_put_context(context, _key, value) when value in [nil, "", []], do: context
  defp maybe_put_context(context, key, value), do: Map.put(context, key, value)

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> value
  end

  defp normalize_atom(value), do: value
end
