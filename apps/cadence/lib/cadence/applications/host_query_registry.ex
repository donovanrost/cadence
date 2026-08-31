defmodule Cadence.Applications.HostQueryRegistry do
  @moduledoc "Bounded registry for application-owned host compatibility queries."

  @max_providers 16
  @contributors [Cadence.Applications.Comms]

  @spec dispatch(Cadence.Auth.Scope.t(), Cadence.Applications.HostContext.t(), map()) ::
          :not_handled | {:ok, map()} | {:error, term()}
  def dispatch(scope, host_context, params) when is_map(params) do
    query_id = Map.get(params, "queryId")

    case provider(query_id) do
      {:ok, provider} ->
        provider.query(scope, host_context, params, query_id)

      :error ->
        if is_binary(query_id) and not Map.has_key?(params, "applicationKey"),
          do: {:error, :unsupported_application_query},
          else: :not_handled
    end
  end

  defp provider(query_id) when is_binary(query_id) do
    providers()
    |> Enum.find_value(:error, fn provider ->
      if Code.ensure_loaded?(provider) and
           function_exported?(provider, :query_id, 0) and
           function_exported?(provider, :query, 4) and provider.query_id() == query_id,
         do: {:ok, provider},
         else: nil
    end)
  end

  defp provider(_query_id), do: :error

  defp providers do
    providers = Enum.flat_map(@contributors, & &1.host_query_providers())
    if length(providers) <= @max_providers, do: providers, else: []
  end
end
