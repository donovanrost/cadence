defmodule Cadence.Applications.HostQueryRegistry do
  @moduledoc "Bounded, identity-bound registry for compatibility host queries."

  alias Cadence.Applications.JSONBoundary

  @max_providers 16
  @contributors [Cadence.Applications.Comms]

  @type provider_key :: {binary(), binary()}

  @spec providers() :: %{optional(provider_key()) => module()}
  def providers, do: providers(@contributors)

  @doc false
  @spec providers([module()]) :: %{optional(provider_key()) => module()}
  def providers(contributors) when is_list(contributors) do
    with true <- length(contributors) <= @max_providers,
         {:ok, provider_list} <- collect_providers(contributors),
         true <- length(provider_list) <= @max_providers,
         true <- unique?(Enum.map(provider_list, &{&1.application_key, &1.query_id})),
         true <- unique?(Enum.map(provider_list, & &1.application_key)),
         true <- unique?(Enum.map(provider_list, & &1.query_id)) do
      Map.new(provider_list, fn provider ->
        {{provider.application_key, provider.query_id}, provider.module}
      end)
    else
      _invalid -> %{}
    end
  end

  def providers(_contributors), do: %{}

  @spec fetch(binary(), binary()) :: {:ok, module()} | {:error, :unknown_application_query}
  def fetch(application_key, query_id) when is_binary(application_key) and is_binary(query_id) do
    case Map.fetch(providers(), {application_key, query_id}) do
      {:ok, provider} when is_atom(provider) ->
        {:ok, provider}

      _missing ->
        {:error, :unknown_application_query}
    end
  end

  def fetch(_application_key, _query_id), do: {:error, :unknown_application_query}

  @spec dispatch(Cadence.Auth.Scope.t(), Cadence.Applications.HostContext.t(), map()) ::
          :not_handled | {:ok, map()} | {:error, term()}
  def dispatch(scope, host_context, params) when is_map(params) do
    registered_providers = providers()

    if registered_providers != %{} do
      dispatch(scope, host_context, params, registered_providers)
    else
      {:error, :invalid_application_host_query_provider_registry}
    end
  end

  def dispatch(_scope, _host_context, _params), do: {:error, :invalid_application_request}

  @doc false
  @spec dispatch(
          Cadence.Auth.Scope.t(),
          Cadence.Applications.HostContext.t(),
          map(),
          %{optional(provider_key()) => module()}
        ) :: :not_handled | {:ok, map()} | {:error, term()}
  def dispatch(scope, host_context, params, registered_providers)
      when is_map(params) and is_map(registered_providers) do
    if registered_providers != %{} and valid_registered_providers?(registered_providers) do
      dispatch_request(scope, host_context, params, registered_providers)
    else
      {:error, :invalid_application_host_query_provider_registry}
    end
  end

  def dispatch(_scope, _host_context, _params, _registered_providers),
    do: {:error, :invalid_application_request}

  defp dispatch_request(scope, host_context, params, registered_providers) do
    query_id = Map.get(params, "queryId")
    application_key = Map.get(params, "applicationKey")

    case {application_key, query_id} do
      {application_key, query_id} when is_binary(application_key) and is_binary(query_id) ->
        dispatch_registered_query(
          scope,
          host_context,
          params,
          registered_providers,
          application_key,
          query_id
        )

      {nil, query_id} when is_binary(query_id) ->
        identity_mismatch_or_not_handled(registered_providers, query_id)

      {_invalid_application_key, query_id} when is_binary(query_id) ->
        {:error, :application_query_identity_mismatch}

      _invalid ->
        :not_handled
    end
  end

  defp dispatch_registered_query(
         scope,
         host_context,
         params,
         registered_providers,
         application_key,
         query_id
       ) do
    case Map.fetch(registered_providers, {application_key, query_id}) do
      {:ok, provider} ->
        dispatch_provider(scope, host_context, params, provider, application_key, query_id)

      :error ->
        identity_mismatch_or_not_handled(registered_providers, query_id)
    end
  end

  defp dispatch_provider(scope, host_context, params, provider, application_key, query_id) do
    if provider_matches_identity?(provider, application_key, query_id),
      do: invoke(provider, scope, host_context, params, query_id),
      else: {:error, :invalid_application_host_query_provider_registry}
  end

  defp collect_providers(contributors) do
    Enum.reduce_while(contributors, {:ok, []}, fn contributor, {:ok, acc} ->
      with {:ok, modules} <- contributor_modules(contributor),
           {:ok, entries} <- provider_entries(modules),
           true <- length(acc) + length(entries) <= @max_providers do
        {:cont, {:ok, acc ++ entries}}
      else
        _invalid -> {:halt, {:error, :invalid_application_host_query_provider_registry}}
      end
    end)
  end

  defp contributor_modules(contributor) when is_atom(contributor) do
    if Code.ensure_loaded?(contributor) and
         function_exported?(contributor, :host_query_providers, 0) do
      case safe_apply(contributor, :host_query_providers, []) do
        {:ok, modules} when is_list(modules) and length(modules) <= @max_providers ->
          {:ok, modules}

        _invalid ->
          {:error, :invalid_application_host_query_provider_registry}
      end
    else
      {:error, :invalid_application_host_query_provider_registry}
    end
  end

  defp contributor_modules(_contributor),
    do: {:error, :invalid_application_host_query_provider_registry}

  defp provider_entries(modules), do: reduce_provider_entries(modules)

  defp reduce_provider_entries(modules) when is_list(modules) do
    modules
    |> Enum.reduce_while({:ok, []}, &collect_provider_entry/2)
    |> normalize_provider_entries()
  end

  defp reduce_provider_entries(_modules),
    do: {:error, :invalid_application_host_query_provider_registry}

  defp collect_provider_entry(module, {:ok, acc}) do
    case provider_entry(module) do
      {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp normalize_provider_entries({:ok, entries}), do: {:ok, Enum.reverse(entries)}
  defp normalize_provider_entries({:error, reason}), do: {:error, reason}

  defp provider_entry(module) when is_atom(module) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :application_key, 0),
         true <- function_exported?(module, :query_id, 0),
         true <- function_exported?(module, :query, 4),
         {:ok, application_key} <- safe_apply(module, :application_key, []),
         {:ok, query_id} <- safe_apply(module, :query_id, []),
         true <- valid_identity?(application_key),
         true <- valid_identity?(query_id) do
      {:ok, %{module: module, application_key: application_key, query_id: query_id}}
    else
      _invalid -> {:error, :invalid_application_host_query_provider_registry}
    end
  end

  defp provider_entry(_module),
    do: {:error, :invalid_application_host_query_provider_registry}

  defp invoke(provider, scope, host_context, params, query_id) do
    if is_atom(provider) do
      with true <- Code.ensure_loaded?(provider),
           true <- function_exported?(provider, :query, 4),
           {:ok, result} <- safe_apply(provider, :query, [scope, host_context, params, query_id]),
           {:ok, result} <- valid_output(result) do
        {:ok, result}
      else
        {:error, :provider_exception} -> {:error, :invalid_application_host_query_output}
        {:error, :invalid_output} -> {:error, :invalid_application_host_query_output}
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_application_host_query}
      end
    else
      {:error, :invalid_application_host_query_provider_registry}
    end
  end

  defp valid_output({:ok, value}) when is_map(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe} -> {:ok, safe}
      {:error, reason} -> {:error, output_error(reason)}
    end
  end

  defp valid_output({:error, reason}), do: {:error, reason}
  defp valid_output(_invalid), do: {:error, :invalid_output}

  defp output_error(reason)
       when reason in [:depth, :map_items, :list_items, :string, :document_bytes],
       do: :application_host_query_output_bounds_exceeded

  defp output_error(_reason), do: :invalid_output

  defp provider_matches_identity?(provider, application_key, query_id) when is_atom(provider) do
    with true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :application_key, 0),
         true <- function_exported?(provider, :query_id, 0),
         {:ok, ^application_key} <- safe_apply(provider, :application_key, []),
         {:ok, ^query_id} <- safe_apply(provider, :query_id, []) do
      true
    else
      _invalid -> false
    end
  end

  defp provider_matches_identity?(_provider, _application_key, _query_id), do: false

  defp valid_registered_providers?(registered_providers)
       when map_size(registered_providers) <= @max_providers do
    entries = Map.to_list(registered_providers)

    with true <- Enum.all?(entries, &valid_registered_entry?/1),
         keys <- Enum.map(entries, &elem(&1, 0)),
         true <- unique?(Enum.map(keys, &elem(&1, 0))),
         true <- unique?(Enum.map(keys, &elem(&1, 1))) do
      true
    else
      _invalid -> false
    end
  end

  defp valid_registered_providers?(_registered_providers), do: false

  defp valid_registered_entry?({{application_key, query_id}, provider}) do
    valid_identity?(application_key) and valid_identity?(query_id) and
      provider_matches_identity?(provider, application_key, query_id)
  end

  defp valid_registered_entry?(_entry), do: false

  defp identity_mismatch_or_not_handled(registered_providers, query_id) do
    if Enum.any?(Map.keys(registered_providers), fn
         {_application_key, ^query_id} -> true
         _other -> false
       end) do
      {:error, :application_query_identity_mismatch}
    else
      :not_handled
    end
  end

  defp valid_identity?(value) when is_binary(value) and value != "" do
    case JSONBoundary.validate(value) do
      :ok -> true
      _invalid -> false
    end
  end

  defp valid_identity?(_value), do: false

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp safe_apply(module, function, arguments) do
    {:ok, apply(module, function, arguments)}
  rescue
    _exception -> {:error, :provider_exception}
  catch
    _kind, _value -> {:error, :provider_exception}
  end
end
