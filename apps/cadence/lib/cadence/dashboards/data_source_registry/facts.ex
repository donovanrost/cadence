defmodule Cadence.Dashboards.DataSourceRegistry.Facts do
  @moduledoc false

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceFacts
  }

  alias Cadence.DataSources.DataSource

  def fetch(%PlannedSourceRequest{} = request, opts, resolve, warning)
      when is_list(opts) and is_function(resolve, 2) and is_function(warning, 5) do
    with {:ok, %ResolvedSourceBinding{} = resolved_binding} <- resolve.(request, opts),
         {:ok, adapter} <- adapter_for(request, resolved_binding, warning) do
      case adapter.facts(request, Keyword.put(opts, :source_binding, resolved_binding)) do
        {:ok, facts} ->
          {:ok, SourceFacts.normalize(facts)}

        {:error, %ResolveWarning{} = resolve_warning} ->
          {:error, resolve_warning}

        _other ->
          {:error,
           warning.(
             request,
             :invalid_source_facts,
             :error,
             "Source adapter returned invalid facts",
             %{adapter: inspect(resolved_binding.data_source.adapter)}
           )}
      end
    end
  end

  defp adapter_for(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{data_source: %DataSource{adapter: adapter}},
         warning
       )
       when is_atom(adapter) and not is_nil(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :facts, 2) do
      {:ok, adapter}
    else
      {:error,
       warning.(
         request,
         :unsupported_source_adapter,
         :error,
         "Source adapter does not expose facts",
         %{
           adapter: inspect(adapter),
           required_callback: :facts
         }
       )}
    end
  end

  defp adapter_for(%PlannedSourceRequest{} = request, %ResolvedSourceBinding{}, warning) do
    {:error,
     warning.(
       request,
       :unsupported_source_adapter,
       :error,
       "Source binding has no source adapter",
       %{
         required_callback: :facts
       }
     )}
  end
end
