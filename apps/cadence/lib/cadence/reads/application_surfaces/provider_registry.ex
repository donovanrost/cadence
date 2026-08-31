defmodule Cadence.Reads.ApplicationSurfaces.ProviderRegistry do
  @moduledoc "Generic bounded registry for application-owned surface query contributions."

  alias Cadence.Applications.SurfaceQueryContribution

  @max_contributions 64

  @spec contributions() :: [SurfaceQueryContribution.t()]
  def contributions do
    Enum.flat_map(
      [
        Cadence.Applications.Comms,
        Cadence.Applications.TelemetryDecom,
        Cadence.Applications.DerivedTelemetry,
        Cadence.Applications.Limits
      ],
      & &1.surface_query_contributions()
    )
  end

  @spec providers() :: %{optional(binary()) => module()}
  def providers, do: providers(contributions())

  @spec providers([SurfaceQueryContribution.t()]) :: %{optional(binary()) => module()}
  def providers(contributions) when is_list(contributions) do
    if length(contributions) <= @max_contributions,
      do: build_provider_map(contributions),
      else: %{}
  end

  defp build_provider_map(contributions) do
    Enum.reduce_while(contributions, %{}, fn
      %SurfaceQueryContribution{query_id: query_id, provider: provider}, acc
      when is_binary(query_id) and is_atom(provider) ->
        put_provider(acc, query_id, provider)

      _invalid, _acc ->
        {:halt, %{}}
    end)
  end

  defp put_provider(acc, query_id, provider) do
    if Map.has_key?(acc, query_id),
      do: {:halt, %{}},
      else: {:cont, Map.put(acc, query_id, provider)}
  end

  @spec fetch(binary()) :: {:ok, module()} | {:error, :unknown_application_surface_query}
  def fetch(query_id) when is_binary(query_id) do
    case Map.fetch(providers(), query_id) do
      {:ok, provider} when is_atom(provider) ->
        if Code.ensure_loaded?(provider) and function_exported?(provider, :load, 3),
          do: {:ok, provider},
          else: {:error, :unknown_application_surface_query}

      _other ->
        {:error, :unknown_application_surface_query}
    end
  end

  def fetch(_query_id), do: {:error, :unknown_application_surface_query}

  @doc "Dispatches a request through the supplied bounded provider map."
  @spec dispatch(Cadence.Auth.Scope.t(), Cadence.Applications.HostContext.t(), map(), map()) ::
          {:ok, term()} | {:error, term()}
  def dispatch(scope, host_context, request, registered_providers)
      when is_map(request) and is_map(registered_providers) do
    case Map.get(registered_providers, request.query_id) do
      provider when is_atom(provider) ->
        if Code.ensure_loaded?(provider) and function_exported?(provider, :load, 3),
          do: provider.load(scope, host_context, request),
          else: {:error, :invalid_application_surface_provider_registry}

      _missing ->
        {:error, :unknown_application_surface_query}
    end
  end

  @spec validate([map()], map()) :: :ok | {:error, :invalid_application_surface_provider_registry}
  def validate(definitions, registered_providers)
      when is_list(definitions) and is_map(registered_providers) do
    contributed_query_ids = MapSet.new(Map.keys(registered_providers))

    required_query_ids =
      for definition <- definitions,
          surface <- definition.surfaces,
          query_id = Map.get(surface.data_contract, :query_id),
          is_binary(query_id),
          declarative_renderer?(surface) or MapSet.member?(contributed_query_ids, query_id),
          do: query_id

    registered_query_ids = Map.keys(registered_providers)

    if length(required_query_ids) <= @max_contributions and
         unique?(required_query_ids) and
         same_identities?(required_query_ids, registered_query_ids) and
         Enum.all?(registered_providers, fn {_query_id, provider} ->
           Code.ensure_loaded?(provider) and function_exported?(provider, :load, 3)
         end) do
      :ok
    else
      {:error, :invalid_application_surface_provider_registry}
    end
  end

  def validate(_definitions, _registered_providers),
    do: {:error, :invalid_application_surface_provider_registry}

  defp same_identities?(left, right), do: MapSet.equal?(MapSet.new(left), MapSet.new(right))
  defp unique?(identities), do: length(identities) == length(Enum.uniq(identities))

  defp declarative_renderer?(%{renderer: {:declarative, "cadence.host.surface.v1"}}), do: true
  defp declarative_renderer?(_surface), do: false
end
