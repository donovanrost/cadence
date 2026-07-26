defmodule Cadence.Reads.ApplicationReferences do
  @moduledoc """
  Host dispatcher for reference data declared by an installed application surface.

  Reference identities are compiled into the registered surface. Every lookup
  rechecks the exact surface, operator authority, active installation, and
  application version before invoking a registered provider.
  """

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    HostContext,
    Registry,
    SurfaceDefinition
  }

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Extensions.Presentation.ReferenceDefinition
  alias Cadence.Reads.ApplicationSurfaces.ReferenceResolver

  @spec resolve(
          Scope.t(),
          HostContext.t(),
          binary(),
          pos_integer(),
          SurfaceDefinition.t(),
          binary()
        ) :: {:ok, Cadence.Extensions.Presentation.ReferencePage.t()} | {:error, term()}
  def resolve(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_key,
        application_version,
        %SurfaceDefinition{} = surface,
        reference_id
      )
      when is_binary(application_key) and is_integer(application_version) and
             is_binary(reference_id) do
    with {:ok, reference} <-
           fetch_authorized_reference(
             current_scope,
             host_context,
             application_key,
             application_version,
             surface,
             reference_id
           ) do
      ReferenceResolver.resolve_reference(current_scope, host_context, reference)
    end
  end

  @spec search(
          Scope.t(),
          HostContext.t(),
          binary(),
          pos_integer(),
          SurfaceDefinition.t(),
          binary(),
          binary()
        ) :: {:ok, Cadence.Extensions.Presentation.ReferencePage.t()} | {:error, term()}
  def search(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_key,
        application_version,
        %SurfaceDefinition{} = surface,
        reference_id,
        query
      )
      when is_binary(application_key) and is_integer(application_version) and
             is_binary(reference_id) and is_binary(query) do
    with {:ok, reference} <-
           fetch_authorized_reference(
             current_scope,
             host_context,
             application_key,
             application_version,
             surface,
             reference_id
           ) do
      ReferenceResolver.search(current_scope, host_context, reference, query)
    end
  end

  defp fetch_authorized_reference(
         current_scope,
         host_context,
         application_key,
         application_version,
         surface,
         reference_id
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
         :ok <- ensure_installation_version(installation, application_version) do
      fetch_reference(surface, reference_id)
    end
  end

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

  defp fetch_reference(%SurfaceDefinition{references: references}, reference_id) do
    case Map.fetch(references, reference_id) do
      {:ok, %ReferenceDefinition{} = reference} -> {:ok, reference}
      {:ok, _invalid} -> {:error, :invalid_application_surface_reference}
      :error -> {:error, :unknown_application_surface_reference}
    end
  end
end
