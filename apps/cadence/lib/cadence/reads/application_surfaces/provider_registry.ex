defmodule Cadence.Reads.ApplicationSurfaces.ProviderRegistry do
  @moduledoc "Generic bounded registry for application-owned surface query contributions."

  alias Cadence.Applications.{
    JSONBoundary,
    SurfaceDefinition,
    SurfaceQueryContribution,
    SurfaceQueryRequest
  }

  @max_contributions 64
  @optional_contributors [CadenceWeb.ApplicationContributions.OrganizationAdmin]

  @compile {:no_warn_undefined,
            {CadenceWeb.ApplicationContributions.OrganizationAdmin, :surface_query_contributions,
             0}}

  @type provider_key :: {binary(), binary()}

  @spec contributions() :: [SurfaceQueryContribution.t()]
  def contributions do
    case collect_contributions(
           [
             Cadence.Applications.Comms,
             Cadence.Applications.Spacecraft,
             Cadence.Applications.MissionCatalog,
             Cadence.Applications.TelemetryDecom,
             Cadence.Applications.DerivedTelemetry,
             Cadence.Applications.Limits
           ] ++ optional_contributors()
         ) do
      {:ok, contributions} -> contributions
      {:error, _reason} -> []
    end
  end

  @spec providers() :: %{optional(provider_key()) => module()}
  def providers, do: providers(contributions())

  @spec providers([SurfaceQueryContribution.t()]) :: %{optional(provider_key()) => module()}
  def providers(contributions) when is_list(contributions) do
    with true <- length(contributions) <= @max_contributions,
         {:ok, entries} <- valid_entries(contributions),
         true <- unique?(Enum.map(entries, & &1.key)),
         true <- unique?(Enum.map(entries, & &1.query_id)) do
      Map.new(entries, fn entry -> {entry.key, entry.provider} end)
    else
      _invalid -> %{}
    end
  end

  def providers(_contributions), do: %{}

  @spec fetch(binary(), binary()) ::
          {:ok, module()} | {:error, :unknown_application_surface_query}
  def fetch(application_key, query_id)
      when is_binary(application_key) and is_binary(query_id) do
    case Map.fetch(providers(), {application_key, query_id}) do
      {:ok, provider} when is_atom(provider) -> {:ok, provider}
      _missing -> {:error, :unknown_application_surface_query}
    end
  end

  def fetch(_application_key, _query_id),
    do: {:error, :unknown_application_surface_query}

  @doc "Dispatches a request through the supplied bounded provider map."
  @spec dispatch(
          Cadence.Auth.Scope.t(),
          Cadence.Applications.HostContext.t(),
          Cadence.Applications.SurfaceQueryRequest.t(),
          %{optional(provider_key()) => module()}
        ) :: {:ok, term()} | {:error, term()}
  def dispatch(scope, host_context, %SurfaceQueryRequest{} = request, registered_providers)
      when is_map(registered_providers) do
    if registered_providers != %{} and valid_registered_providers?(registered_providers) do
      dispatch_registered(scope, host_context, request, registered_providers)
    else
      {:error, :invalid_application_surface_provider_registry}
    end
  end

  def dispatch(_scope, _host_context, _request, _registered_providers),
    do: {:error, :invalid_application_surface_provider_registry}

  defp dispatch_registered(scope, host_context, request, registered_providers) do
    case Map.fetch(registered_providers, {request.application_key, request.query_id}) do
      {:ok, provider} -> invoke(provider, scope, host_context, request)
      :error -> {:error, :unknown_application_surface_query}
    end
  end

  @spec validate([map()], map()) :: :ok | {:error, :invalid_application_surface_provider_registry}
  def validate(definitions, registered_providers)
      when is_list(definitions) and is_map(registered_providers) do
    if Enum.all?(definitions, &valid_definition?/1) do
      declared_keys =
        for definition <- definitions,
            surface <- definition.surfaces,
            query_id = Map.get(surface.data_contract, :query_id),
            is_binary(query_id),
            do: {definition.application_key, query_id}

      registered_keys = Map.keys(registered_providers)

      with {:ok, authoritative_keys} <- authoritative_provider_keys(),
           true <- authoritative_keys != [],
           true <- length(authoritative_keys) <= @max_contributions,
           true <- unique?(authoritative_keys),
           true <- same_identities?(authoritative_keys, registered_keys),
           true <- declares_provider_keys?(authoritative_keys, declared_keys),
           true <- valid_registered_providers?(registered_providers) do
        :ok
      else
        _invalid -> {:error, :invalid_application_surface_provider_registry}
      end
    else
      {:error, :invalid_application_surface_provider_registry}
    end
  end

  def validate(_definitions, _registered_providers),
    do: {:error, :invalid_application_surface_provider_registry}

  defp collect_contributions(contributors) do
    Enum.reduce_while(contributors, {:ok, []}, fn contributor, {:ok, acc} ->
      with true <- is_atom(contributor),
           true <- Code.ensure_loaded?(contributor),
           true <- function_exported?(contributor, :surface_query_contributions, 0),
           {:ok, contributions} <- safe_apply(contributor, :surface_query_contributions, []),
           true <- is_list(contributions),
           true <- length(acc) + length(contributions) <= @max_contributions do
        {:cont, {:ok, acc ++ contributions}}
      else
        _invalid -> {:halt, {:error, :invalid_application_surface_provider_registry}}
      end
    end)
  end

  defp optional_contributors do
    Enum.filter(@optional_contributors, &Code.ensure_loaded?/1)
  end

  defp valid_entries(contributions) do
    Enum.reduce_while(contributions, {:ok, []}, fn
      %SurfaceQueryContribution{
        application_key: application_key,
        application_version: application_version,
        query_id: query_id,
        query_version: query_version,
        provider: provider
      },
      {:ok, acc} ->
        if valid_contribution?(
             application_key,
             application_version,
             query_id,
             query_version,
             provider
           ) do
          {:cont,
           {:ok,
            [
              %{
                key: {application_key, query_id},
                query_id: query_id,
                provider: provider
              }
              | acc
            ]}}
        else
          {:halt, {:error, :invalid_application_surface_provider_registry}}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_application_surface_provider_registry}}
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_contribution?(
         application_key,
         application_version,
         query_id,
         query_version,
         provider
       ) do
    Enum.all?([
      valid_identity?(application_key),
      valid_version?(application_version),
      valid_identity?(query_id),
      valid_version?(query_version),
      valid_provider_identity?(provider, application_key)
    ])
  end

  defp valid_version?(version), do: is_integer(version) and version > 0

  defp valid_provider_identity?(provider, application_key) do
    valid_provider?(provider) and provider_matches_application_key?(provider, application_key)
  end

  defp invoke(provider, scope, host_context, request) when is_atom(provider) do
    with true <- valid_provider?(provider),
         {:ok, result} <- safe_apply(provider, :load, [scope, host_context, request]) do
      normalize_provider_result(result)
    else
      _invalid -> {:error, :invalid_application_surface_provider_registry}
    end
  end

  defp invoke(_provider, _scope, _host_context, _request),
    do: {:error, :invalid_application_surface_provider_registry}

  defp normalize_provider_result({:ok, result}), do: {:ok, result}
  defp normalize_provider_result({:error, reason}), do: {:error, reason}

  defp normalize_provider_result(_invalid),
    do: {:error, :invalid_application_surface_provider_registry}

  defp valid_key?({application_key, query_id}),
    do: valid_identity?(application_key) and valid_identity?(query_id)

  defp valid_key?(_key), do: false

  defp valid_provider?(provider) when is_atom(provider) do
    Code.ensure_loaded?(provider) and function_exported?(provider, :load, 3)
  end

  defp valid_provider?(_provider), do: false

  defp valid_registered_providers?(registered_providers)
       when map_size(registered_providers) <= @max_contributions do
    entries = Map.to_list(registered_providers)

    with true <- Enum.all?(entries, &valid_registered_entry?/1),
         keys <- Enum.map(entries, &elem(&1, 0)),
         true <- unique?(keys),
         true <- unique?(Enum.map(keys, &elem(&1, 1))) do
      true
    else
      _invalid -> false
    end
  end

  defp valid_registered_providers?(_registered_providers), do: false

  defp valid_registered_entry?({key, provider}),
    do:
      valid_key?(key) and valid_provider?(provider) and
        provider_matches_application_key?(provider, elem(key, 0))

  defp valid_registered_entry?(_entry), do: false

  defp valid_definition?(%{application_key: application_key, surfaces: surfaces})
       when is_list(surfaces) do
    valid_identity?(application_key) and
      Enum.all?(surfaces, &(SurfaceDefinition.validate(&1) == :ok))
  end

  defp valid_definition?(_definition), do: false

  defp valid_identity?(value) when is_binary(value) and value != "" do
    JSONBoundary.validate(value) == :ok
  end

  defp valid_identity?(_value), do: false

  defp provider_matches_application_key?(provider, application_key) do
    function_exported?(provider, :application_key, 0) and
      case safe_apply(provider, :application_key, []) do
        {:ok, ^application_key} -> true
        _invalid -> false
      end
  end

  defp authoritative_provider_keys do
    case valid_entries(contributions()) do
      {:ok, entries} -> {:ok, Enum.map(entries, & &1.key)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp declares_provider_keys?(authoritative_keys, declared_keys) do
    MapSet.subset?(MapSet.new(authoritative_keys), MapSet.new(declared_keys))
  end

  defp same_identities?(left, right), do: MapSet.equal?(MapSet.new(left), MapSet.new(right))

  defp unique?(identities), do: length(identities) == length(Enum.uniq(identities))

  defp safe_apply(module, function, arguments) do
    {:ok, apply(module, function, arguments)}
  rescue
    _exception -> {:error, :provider_exception}
  catch
    _kind, _value -> {:error, :provider_exception}
  end
end
