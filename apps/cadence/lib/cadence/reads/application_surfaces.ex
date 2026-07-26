defmodule Cadence.Reads.ApplicationSurfaces do
  @moduledoc "Host-owned dispatcher for versioned declarative surface queries."

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    HostContext,
    Registry,
    SurfaceDefinition,
    SurfaceDocument,
    SurfaceQueryRequest
  }

  alias Cadence.Applications.SurfaceElements.GeneratedForm

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Extensions.Presentation.FieldDefinition
  alias Cadence.Reads.ApplicationSurfaces.DerivedTelemetry, as: DerivedTelemetrySurface
  alias Cadence.Reads.ApplicationSurfaces.Limits, as: LimitsSurface
  alias Cadence.Reads.ApplicationSurfaces.ReferenceResolver

  @providers %{
    "cadence.derived_telemetry.manage" => DerivedTelemetrySurface,
    "cadence.limits.manage" => LimitsSurface,
    "cadence.limits.activity" => LimitsSurface
  }

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_surface_provider_registry}
  def validate_providers, do: validate_providers(Registry.all(), @providers)

  @doc false
  @spec validate_providers([ApplicationDefinition.t()], map()) ::
          :ok | {:error, :invalid_application_surface_provider_registry}
  def validate_providers(definitions, providers)
      when is_list(definitions) and is_map(providers) do
    required_query_ids =
      for definition <- definitions,
          surface <- definition.surfaces,
          match?({:declarative, "cadence.host.surface.v1"}, surface.renderer),
          do: Map.get(surface.data_contract, :query_id)

    registered_query_ids = Map.keys(providers)

    if unique?(required_query_ids) and
         same_identities?(required_query_ids, registered_query_ids) and
         Enum.all?(providers, fn {_query_id, provider} ->
           Code.ensure_loaded?(provider) and function_exported?(provider, :load, 3)
         end) do
      :ok
    else
      {:error, :invalid_application_surface_provider_registry}
    end
  end

  def validate_providers(_definitions, _providers),
    do: {:error, :invalid_application_surface_provider_registry}

  @spec load(Scope.t(), HostContext.t(), binary(), pos_integer(), SurfaceDefinition.t(), map()) ::
          {:ok, Cadence.Applications.SurfaceDocument.t()} | {:error, term()}
  def load(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_key,
        application_version,
        %SurfaceDefinition{} = surface,
        params \\ %{}
      )
      when is_binary(application_key) and is_integer(application_version) and is_map(params) do
    with {:ok, document} <-
           load_unresolved_document(
             current_scope,
             host_context,
             application_key,
             application_version,
             surface,
             params
           ),
         {:ok, document} <- bind_reference_contracts(document, surface) do
      ReferenceResolver.resolve(current_scope, host_context, document)
    end
  end

  defp load_unresolved_document(
         current_scope,
         host_context,
         application_key,
         application_version,
         surface,
         params
       ) do
    with {:ok, definition} <- Registry.fetch_available(application_key, application_version),
         :ok <- ensure_declared_surface(definition, surface, host_context),
         :ok <- authorize_surface(current_scope, host_context),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             application_key
           ),
         :ok <- ensure_installation_version(installation, application_version),
         {:ok, query_id, query_version} <- query_contract(surface),
         {:ok, provider} <- fetch_provider(query_id) do
      with {:ok, document} <-
             provider.load(
               current_scope,
               host_context,
               %SurfaceQueryRequest{
                 application_key: application_key,
                 application_version: application_version,
                 surface_id: surface.surface_id,
                 surface_version: surface.version,
                 query_id: query_id,
                 query_version: query_version,
                 params: params
               }
             ),
           :ok <- validate_document(document, surface) do
        {:ok, document}
      end
    end
  end

  defp validate_document(%SurfaceDocument{} = document, %SurfaceDefinition{} = surface) do
    SurfaceDocument.validate(document, surface.actions)
  end

  defp bind_reference_contracts(
         %SurfaceDocument{form: %GeneratedForm{} = form} = document,
         %SurfaceDefinition{} = surface
       ) do
    with {:ok, fields} <- bind_reference_fields(form.fields, surface.references) do
      {:ok, %SurfaceDocument{document | form: %GeneratedForm{form | fields: fields}}}
    end
  end

  defp bind_reference_contracts(%SurfaceDocument{} = document, %SurfaceDefinition{}),
    do: {:ok, document}

  defp bind_reference_fields(fields, references) do
    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, bound_fields} ->
      case bind_reference_field(field, references) do
        {:ok, bound_field} -> {:cont, {:ok, [bound_field | bound_fields]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, bound_fields} -> {:ok, Enum.reverse(bound_fields)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bind_reference_field(
         %FieldDefinition{type: :reference, field: field, reference: inline_reference} =
           definition,
         references
       ) do
    case Map.fetch(references, Atom.to_string(field)) do
      {:ok, declared_reference}
      when is_nil(inline_reference) or inline_reference == declared_reference ->
        {:ok, %FieldDefinition{definition | reference: declared_reference}}

      {:ok, _declared_reference} ->
        {:error, :application_surface_reference_contract_mismatch}

      :error ->
        {:error, :unknown_application_surface_reference}
    end
  end

  defp bind_reference_field(%FieldDefinition{} = field, _references), do: {:ok, field}

  defp ensure_declared_surface(
         %ApplicationDefinition{} = definition,
         %SurfaceDefinition{} = surface,
         %HostContext{placement: placement}
       ) do
    declared? =
      Enum.any?(definition.surfaces, fn declared ->
        declared == surface and declared.scope == placement
      end)

    if declared?, do: :ok, else: {:error, :undeclared_application_surface}
  end

  defp authorize_surface(current_scope, host_context) do
    Policy.authorize(current_scope, :operate_mission, %{
      organization_id: current_scope.organization_id,
      mission_id: host_context.mission_id
    })
  end

  defp ensure_installation_version(
         %ApplicationInstallation{application_version: version},
         version
       ),
       do: :ok

  defp ensure_installation_version(%ApplicationInstallation{}, _requested_version),
    do: {:error, :application_installation_version_mismatch}

  defp query_contract(%SurfaceDefinition{data_contract: data_contract}) do
    case {Map.get(data_contract, :query_id), Map.get(data_contract, :version)} do
      {query_id, version} when is_binary(query_id) and is_integer(version) and version > 0 ->
        {:ok, query_id, version}

      _other ->
        {:error, :invalid_application_surface_query_contract}
    end
  end

  defp fetch_provider(query_id) do
    case Map.fetch(@providers, query_id) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :unknown_application_surface_query}
    end
  end

  defp same_identities?(left, right),
    do: MapSet.equal?(MapSet.new(left), MapSet.new(right))

  defp unique?(identities), do: length(identities) == length(Enum.uniq(identities))
end
