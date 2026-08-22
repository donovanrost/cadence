defmodule Cadence.Reads.ApplicationSurfaces.ReferenceResolver do
  @moduledoc """
  Resolves surface reference contracts through the host's versioned provider registry.

  Providers return typed, bounded data. The resolver converts that data into
  renderer-ready options only after the enclosing surface has been authorized.
  """

  alias Cadence.Applications.{ApplicationDefinition, HostContext, Registry, SurfaceDocument}
  alias Cadence.Applications.SurfaceElements.GeneratedForm
  alias Cadence.Auth.Scope

  alias Cadence.Extensions.Presentation.{
    FieldDefinition,
    ReferenceDefinition,
    ReferenceOption,
    ReferencePage
  }

  alias Cadence.Reads.ApplicationSurfaces.ReferenceProviders.{
    CanonicalTelemetryPoints,
    TelemetryCatalogRevisions
  }

  @max_select_options 500
  @max_search_options 50
  @max_query_length 120

  @providers %{
    "cadence.catalog.telemetry_revisions" => %{1 => TelemetryCatalogRevisions},
    "cadence.telemetry.canonical_points" => %{1 => CanonicalTelemetryPoints}
  }

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_reference_provider_registry}
  def validate_providers, do: validate_providers(Registry.all(), @providers)

  @doc false
  @spec validate_providers([ApplicationDefinition.t()], map()) ::
          :ok | {:error, :invalid_application_reference_provider_registry}
  def validate_providers(definitions, providers)
      when is_list(definitions) and is_map(providers) do
    required_identities =
      for definition <- definitions,
          surface <- definition.surfaces,
          {_field, %ReferenceDefinition{} = reference} <- surface.references,
          do: {reference.provider_id, reference.version}

    registered_identities =
      for {provider_id, versions} <- providers,
          is_map(versions),
          {version, _provider} <- versions,
          do: {provider_id, version}

    if same_identities?(required_identities, registered_identities) and
         valid_provider_modules?(providers) do
      :ok
    else
      {:error, :invalid_application_reference_provider_registry}
    end
  end

  def validate_providers(_definitions, _providers),
    do: {:error, :invalid_application_reference_provider_registry}

  @spec resolve(Scope.t(), HostContext.t(), SurfaceDocument.t()) ::
          {:ok, SurfaceDocument.t()} | {:error, term()}
  def resolve(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %SurfaceDocument{
          form: %GeneratedForm{} = form
        } = document
      ) do
    with {:ok, fields} <- resolve_fields(current_scope, host_context, form.fields) do
      {:ok, %SurfaceDocument{document | form: %GeneratedForm{form | fields: fields}}}
    end
  end

  def resolve(%Scope{}, %HostContext{}, %SurfaceDocument{} = document), do: {:ok, document}

  @spec resolve_reference(Scope.t(), HostContext.t(), ReferenceDefinition.t()) ::
          {:ok, ReferencePage.t()} | {:error, term()}
  def resolve_reference(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %ReferenceDefinition{} = reference
      ) do
    load_page(current_scope, host_context, reference)
  end

  @spec search(Scope.t(), HostContext.t(), ReferenceDefinition.t(), binary()) ::
          {:ok, ReferencePage.t()} | {:error, term()}
  def search(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %ReferenceDefinition{mode: :search} = reference,
        query
      )
      when is_binary(query) do
    with :ok <- validate_search_definition(reference),
         :ok <- validate_query(query),
         {:ok, provider} <- fetch_provider(reference),
         {:ok, page} <-
           provider.search(
             current_scope,
             host_context,
             reference,
             query,
             reference.result_limit
           ),
         :ok <- validate_page(page, reference.result_limit) do
      {:ok, page}
    end
  end

  def search(%Scope{}, %HostContext{}, %ReferenceDefinition{}, _query),
    do: {:error, :reference_not_searchable}

  defp resolve_fields(current_scope, host_context, fields) do
    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, resolved} ->
      case resolve_field(current_scope, host_context, field) do
        {:ok, resolved_field} -> {:cont, {:ok, [resolved_field | resolved]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_field(
         current_scope,
         host_context,
         %FieldDefinition{
           type: :reference,
           reference: %ReferenceDefinition{} = reference
         } = field
       ) do
    with {:ok, page} <- resolve_reference(current_scope, host_context, reference) do
      {:ok, %FieldDefinition{field | reference_page: page}}
    end
  end

  defp resolve_field(_current_scope, _host_context, %FieldDefinition{type: :reference}),
    do: {:error, :invalid_reference_field}

  defp resolve_field(_current_scope, _host_context, %FieldDefinition{reference: reference})
       when not is_nil(reference),
       do: {:error, :invalid_reference_field}

  defp resolve_field(_current_scope, _host_context, %FieldDefinition{} = field),
    do: {:ok, field}

  defp load_page(current_scope, host_context, %ReferenceDefinition{mode: :select} = reference) do
    with {:ok, provider} <- fetch_provider(reference),
         {:ok, page} <-
           provider.search(
             current_scope,
             host_context,
             reference,
             "",
             @max_select_options
           ),
         :ok <- validate_page(page, @max_select_options),
         false <- page.more? do
      {:ok, page}
    else
      true -> {:error, :reference_option_limit_exceeded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_page(current_scope, host_context, %ReferenceDefinition{mode: :search} = reference) do
    with :ok <- validate_search_definition(reference),
         {:ok, provider} <- fetch_provider(reference),
         {:ok, page} <-
           provider.search(
             current_scope,
             host_context,
             reference,
             "",
             reference.result_limit
           ),
         :ok <- validate_page(page, reference.result_limit) do
      {:ok, page}
    end
  end

  defp load_page(_current_scope, _host_context, %ReferenceDefinition{}),
    do: {:error, :invalid_reference_field}

  defp fetch_provider(%ReferenceDefinition{provider_id: provider_id, version: version}) do
    case Map.fetch(@providers, provider_id) do
      {:ok, versions} ->
        case Map.fetch(versions, version) do
          {:ok, provider} -> {:ok, provider}
          :error -> {:error, :unsupported_reference_provider_version}
        end

      :error ->
        {:error, :unknown_reference_provider}
    end
  end

  defp valid_provider_modules?(providers) do
    Enum.all?(providers, fn {_provider_id, versions} ->
      is_map(versions) and
        Enum.all?(versions, fn {_version, provider} ->
          Code.ensure_loaded?(provider) and function_exported?(provider, :search, 5)
        end)
    end)
  end

  defp same_identities?(left, right),
    do: MapSet.equal?(MapSet.new(left), MapSet.new(right))

  defp validate_search_definition(%ReferenceDefinition{result_limit: result_limit})
       when is_integer(result_limit) and result_limit > 0 and result_limit <= @max_search_options,
       do: :ok

  defp validate_search_definition(%ReferenceDefinition{}),
    do: {:error, :invalid_reference_search_limit}

  defp validate_query(query) when byte_size(query) <= @max_query_length, do: :ok
  defp validate_query(_query), do: {:error, :reference_query_too_long}

  defp validate_page(%ReferencePage{query: query, options: options, more?: more?}, limit)
       when is_binary(query) and is_list(options) and is_boolean(more?) do
    cond do
      length(options) > limit ->
        {:error, :reference_option_limit_exceeded}

      not Enum.all?(options, &valid_option?/1) ->
        {:error, :invalid_reference_options}

      options |> Enum.map(& &1.value) |> Enum.uniq() |> length() != length(options) ->
        {:error, :duplicate_reference_options}

      true ->
        :ok
    end
  end

  defp validate_page(_page, _limit), do: {:error, :invalid_reference_options}

  defp valid_option?(%ReferenceOption{value: value, label: label, description: description}) do
    is_binary(value) and value != "" and is_binary(label) and label != "" and
      (is_nil(description) or is_binary(description))
  end

  defp valid_option?(_option), do: false
end
