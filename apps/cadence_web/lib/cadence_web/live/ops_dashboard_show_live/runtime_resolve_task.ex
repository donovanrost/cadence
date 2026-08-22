defmodule CadenceWeb.OpsDashboardShowLive.RuntimeResolveTask do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.EngineResolution

  @spec resolve(term(), term(), term(), term(), keyword()) :: {term(), term()}
  def resolve(
        resolve_id,
        request,
        comparison_request,
        resolution_context,
        opts \\ []
      ) do
    {resolve_id, resolve_request_bundle(request, comparison_request, resolution_context, opts)}
  end

  defp resolve_request_bundle(request, comparison_request, resolution_context, opts) do
    resolve_request_bundle_fn(opts).(request, comparison_request, resolution_context)
  end

  defp resolve_request_bundle_fn(opts) do
    Keyword.get(opts, :resolve_request_bundle, &EngineResolution.resolve_request_bundle/3)
  end
end
