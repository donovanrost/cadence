defmodule Cadence.Dashboards.SourceRegistry.SourceIdentity do
  @moduledoc false

  alias Cadence.Dashboards.{DataContext, PlannedSourceRequest, ResolvedSourceBinding}

  @spec from(PlannedSourceRequest.t(), ResolvedSourceBinding.t()) :: map()
  def from(%PlannedSourceRequest{} = request, %ResolvedSourceBinding{} = resolved_binding) do
    binding = resolved_binding.binding
    data_source = resolved_binding.data_source

    %{
      organization_id:
        request.organization_id || Map.get(binding, :organization_id) ||
          Map.get(data_source, :organization_id),
      mission_id:
        request.mission_id || Map.get(binding, :mission_id) || Map.get(data_source, :mission_id),
      logical_source: request.logical_source || Map.get(binding, :logical_source),
      data_source_id: Map.get(data_source, :data_source_id),
      source_binding_id: Map.get(binding, :binding_id),
      realm: Map.get(binding, :realm),
      replay_run_id:
        DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
          get_attr(request.time_context, :replay_run_id),
      dataset: Map.get(binding, :dataset)
    }
  end

  defp get_attr(%_{} = attrs, key), do: attrs |> Map.from_struct() |> get_attr(key)

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
