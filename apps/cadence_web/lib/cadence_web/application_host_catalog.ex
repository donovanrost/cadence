defmodule CadenceWeb.ApplicationHostCatalog do
  @moduledoc """
  Builds the Phoenix-owned catalog consumed by the first-party plugin SDK.

  Application identity comes from the composed extension catalog and the
  application registry. Installation lifecycle is checked at the requested
  host context, while frontend release coordinates come from the separate
  `ApplicationReleaseRegistry`.
  """

  alias Cadence.Applications.{ApplicationInstallation, ApplicationInstallations, HostContext}
  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Auth.Scope
  alias Cadence.ExtensionCatalog
  alias Cadence.Extensions.{ApplicationContribution, ExtensionPackage}
  alias Cadence.Missions.Mission
  alias Cadence.Spacecraft
  alias CadenceWeb.ApplicationReleaseRegistry

  @application_catalog_schema "cadence.first-party-frontend-catalog.v1"
  @application_host_contract "cadence.application-host.v1"

  @type route_context :: %{
          host_context: HostContext.t(),
          mission: Mission.t(),
          spacecraft: Spacecraft.t() | nil
        }

  @type build_error ::
          :application_catalog_unavailable
          | :application_not_installed
          | :application_installation_disabled
          | :application_installation_uninstalled
          | :application_installation_scope_required
          | :application_unavailable
          | :invalid_application_request
          | :unknown_application_release
          | :unknown_surface
          | term()

  @spec build(Scope.t(), route_context(), keyword()) ::
          {:ok, map()} | {:error, build_error()}
  def build(
        %Scope{} = current_scope,
        %{host_context: %HostContext{}} = route_context,
        opts
      )
      when is_list(opts) do
    with :ok <- validate_session_options(opts),
         {:ok, applications} <- applications(current_scope, route_context, opts) do
      {:ok,
       %{
         "schema" => @application_catalog_schema,
         "hostContract" => @application_host_contract,
         "generatedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "session" => %{
           "sessionId" => Keyword.fetch!(opts, :session_id),
           "csrfToken" => Keyword.fetch!(opts, :csrf_token),
           "bridgeBaseUrl" => Keyword.fetch!(opts, :bridge_base_url),
           "context" => context_document(current_scope, route_context)
         },
         "applications" => applications
       }}
    end
  end

  def build(%Scope{}, %{}, _opts), do: {:error, :application_catalog_unavailable}

  @doc "Resolves one installed application surface without constructing a catalog."
  @spec admit_application(Scope.t(), route_context(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, build_error()}
  def admit_application(current_scope, route_context, application_key, surface_id \\ nil)

  def admit_application(
        %Scope{} = current_scope,
        %{host_context: %HostContext{}} = route_context,
        application_key,
        surface_id
      )
      when is_binary(application_key) do
    with {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             route_context.host_context,
             application_key
           ) do
      registered_application(
        application_key,
        installation,
        route_context.host_context,
        surface_id
      )
    end
  end

  def admit_application(%Scope{}, %{}, _application_key, _surface_id),
    do: {:error, :application_catalog_unavailable}

  @spec scope_document(Scope.t(), route_context()) :: map()
  def scope_document(
        %Scope{organization_id: organization_id},
        %{host_context: %HostContext{} = host_context}
      ) do
    %{
      "organizationId" => organization_id,
      "missionId" => host_context.mission_id,
      "spacecraftId" => host_context.spacecraft_id
    }
  end

  @spec context_document(Scope.t(), route_context()) :: map()
  def context_document(
        %Scope{} = current_scope,
        %{
          host_context: %HostContext{placement: placement, spacecraft_id: spacecraft_id},
          mission: %Mission{mission_id: mission_id, display_name: mission_name},
          spacecraft: spacecraft
        }
      ) do
    %{
      "organizationId" => current_scope.organization_id,
      "missionId" => mission_id,
      "missionName" => mission_name,
      "scope" => Atom.to_string(placement),
      "spacecraftId" => spacecraft_id,
      "spacecraftName" => spacecraft_name(spacecraft),
      "actor" => actor_document(current_scope)
    }
  end

  @spec bridge_base_path(route_context()) :: binary()
  def bridge_base_path(%{host_context: %HostContext{placement: :mission, mission_id: mission_id}}) do
    "/api/cadence/application-host/v1/missions/" <> URI.encode(mission_id)
  end

  def bridge_base_path(%{
        host_context: %HostContext{
          placement: :spacecraft,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        }
      }) do
    "/api/cadence/application-host/v1/missions/" <>
      URI.encode(mission_id) <> "/spacecraft/" <> URI.encode(spacecraft_id)
  end

  @doc "Returns the Phoenix LiveView fallback for an admitted application surface."
  @spec fallback_href(route_context(), binary(), binary() | nil) :: binary()
  def fallback_href(
        %{host_context: %HostContext{placement: :mission, mission_id: mission_id}},
        application_key,
        surface_id
      )
      when is_binary(application_key) do
    application_href("/missions/" <> URI.encode(mission_id), application_key, surface_id)
  end

  def fallback_href(
        %{
          host_context: %HostContext{
            placement: :spacecraft,
            mission_id: mission_id,
            spacecraft_id: spacecraft_id
          }
        },
        application_key,
        surface_id
      )
      when is_binary(application_key) do
    application_href(
      "/missions/" <> URI.encode(mission_id) <> "/spacecraft/" <> URI.encode(spacecraft_id),
      application_key,
      surface_id
    )
  end

  defp applications(current_scope, route_context, opts) do
    manifest_url = Keyword.fetch!(opts, :manifest_url)

    case {Keyword.get(opts, :application_key), Keyword.get(opts, :surface_id)} do
      {nil, nil} ->
        all_applications(current_scope, route_context, manifest_url)

      {application_key, surface_id} when is_binary(application_key) ->
        with {:ok, application} <-
               admit_application(current_scope, route_context, application_key, surface_id) do
          {:ok, [application_document(application, manifest_url)]}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp all_applications(
         %Scope{} = current_scope,
         %{host_context: %HostContext{} = host_context},
         manifest_url
       ) do
    with {:ok, installations} <- ApplicationInstallations.list(current_scope, host_context) do
      installed_applications =
        installations
        |> Enum.filter(&(&1.lifecycle_state == :installed))
        |> Enum.flat_map(&installed_application_document(&1, host_context, manifest_url))

      applications =
        compatibility_applications(host_context, manifest_url) ++ installed_applications

      if applications == [] do
        {:error, :application_catalog_unavailable}
      else
        {:ok, applications}
      end
    end
  end

  defp all_applications(%Scope{}, %{}, _manifest_url),
    do: {:error, :application_catalog_unavailable}

  defp registered_application(
         application_key,
         %ApplicationInstallation{application_version: application_version},
         %HostContext{placement: placement},
         surface_id
       ) do
    with {:ok, definition} <-
           ExtensionCatalog.fetch_available_application(application_key, application_version),
         true <- placement in definition.installable_scopes,
         {:ok, surface, release} <-
           resolve_surface(definition, placement, application_key, surface_id),
         {:ok, package} <- package_for(application_key, application_version) do
      {:ok,
       %{
         definition: definition,
         package: package,
         release: release,
         surface: surface
       }}
    else
      false ->
        {:error, :application_unavailable}

      {:error, :unknown_application} ->
        {:error, :application_unavailable}

      {:error, :application_unavailable} ->
        {:error, :application_unavailable}

      {:error, :unsupported_application_version} ->
        {:error, :application_unavailable}

      {:error, :invalid_application_definition} ->
        {:error, :application_unavailable}

      {:error, :unknown_surface} = error ->
        error

      {:error, :unknown_application_release} = error ->
        error

      {:error, :unknown_application_contribution} ->
        {:error, :application_unavailable}

      {:error, :unsupported_application_contribution_version} ->
        {:error, :application_unavailable}
    end
  end

  defp resolve_surface(definition, placement, application_key, nil) do
    definition
    |> ApplicationRegistry.workspace_surfaces(placement)
    |> Enum.find_value({:error, :unknown_application_release}, fn surface ->
      case ApplicationReleaseRegistry.fetch(
             application_key,
             definition.version,
             surface.surface_id,
             surface.version
           ) do
        {:ok, release} -> {:ok, surface, release}
        {:error, :unknown_application_release} -> nil
      end
    end)
  end

  defp resolve_surface(definition, placement, application_key, surface_id)
       when is_binary(surface_id) do
    with {:ok, surface} <- ApplicationRegistry.fetch_surface(definition, placement, surface_id),
         {:ok, release} <-
           ApplicationReleaseRegistry.fetch(
             application_key,
             definition.version,
             surface.surface_id,
             surface.version
           ) do
      {:ok, surface, release}
    end
  end

  defp package_for(application_key, application_version) do
    case Enum.find(
           ExtensionCatalog.available(),
           &package_contributes?(&1, application_key, application_version)
         ) do
      %ExtensionPackage{} = package -> {:ok, package}
      nil -> {:error, :application_unavailable}
    end
  end

  defp installed_application_document(installation, host_context, manifest_url) do
    case registered_application(
           installation.application_key,
           installation,
           host_context,
           nil
         ) do
      {:ok, application} -> [application_document(application, manifest_url)]
      {:error, _reason} -> []
    end
  end

  defp package_contributes?(
         %ExtensionPackage{contributions: contributions},
         application_key,
         application_version
       ) do
    Enum.any?(contributions, fn
      %ApplicationContribution{
        application_key: ^application_key,
        application_version: ^application_version
      } ->
        true

      _contribution ->
        false
    end)
  end

  defp application_document(
         %{definition: definition, package: package, release: release, surface: surface},
         manifest_url
       ) do
    %{
      "applicationKey" => definition.application_key,
      "applicationVersion" => definition.version,
      "displayName" => definition.display_name,
      "description" => definition.description,
      "package" => %{
        "packageId" => package.package_id,
        "version" => package.version
      },
      "surface" => surface_document(surface, release),
      "release" => release_document(release, manifest_url)
    }
  end

  defp surface_document(surface, release) do
    %{
      "surfaceId" => surface.surface_id,
      "version" => surface.version,
      "purpose" => Atom.to_string(surface.purpose),
      "scope" => Atom.to_string(surface.scope),
      "placement" => Atom.to_string(surface.placement),
      "navigation" => %{
        "label" => Map.get(surface.navigation, :label, surface.surface_id),
        "order" => Map.get(surface.navigation, :order, 0)
      },
      "dataContract" => %{
        "id" => Map.get(surface.data_contract, :query_id),
        "version" => Map.get(surface.data_contract, :version)
      },
      "actions" => surface.actions,
      "renderer" => %{
        "kind" => "federated-vue",
        "exposedModule" => release.exposed_module
      }
    }
  end

  defp release_document(release, manifest_url) do
    %{
      "federation" => Atom.to_string(release.federation),
      "releaseId" => release.release_id,
      "remoteName" => release.remote_name,
      "manifestUrl" => manifest_url.(release.manifest_path),
      "exposedModule" => release.exposed_module
    }
  end

  defp compatibility_applications(%HostContext{placement: :mission}, manifest_url) do
    {:ok, release} = ApplicationReleaseRegistry.fetch("comms_overview", 1, "overview", 1)

    [
      %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "displayName" => "Communications Overview",
        "description" => "Review the saved communications setup for a mission.",
        "package" => %{"packageId" => "cadence.comms_overview", "version" => 1},
        "surface" => %{
          "surfaceId" => "overview",
          "version" => 1,
          "purpose" => "overview",
          "scope" => "mission",
          "placement" => "application_workspace",
          "navigation" => %{"label" => "Overview", "order" => 10},
          "dataContract" => %{"id" => "cadence.comms.overview", "version" => 1},
          "actions" => [],
          "renderer" => %{
            "kind" => "federated-vue",
            "exposedModule" => release.exposed_module
          }
        },
        "release" => release_document(release, manifest_url)
      }
    ]
  end

  defp compatibility_applications(%HostContext{}, _manifest_url), do: []

  defp application_href(base_path, application_key, nil),
    do: base_path <> "/applications/" <> URI.encode(application_key)

  defp application_href(base_path, application_key, surface_id),
    do:
      base_path <>
        "/applications/" <> URI.encode(application_key) <> "/" <> URI.encode(surface_id)

  defp actor_document(%Scope{user: %{display_name: display_name}}) do
    %{"displayName" => display_name, "permissions" => ["applications:view"]}
  end

  defp actor_document(%Scope{}) do
    %{"displayName" => "Authenticated actor", "permissions" => ["applications:view"]}
  end

  defp spacecraft_name(%Spacecraft{display_name: display_name}), do: display_name
  defp spacecraft_name(nil), do: nil

  defp validate_session_options(opts) do
    with true <- valid_text?(Keyword.get(opts, :session_id)),
         true <- valid_text?(Keyword.get(opts, :csrf_token)),
         true <- valid_path?(Keyword.get(opts, :bridge_base_url)),
         true <- is_function(Keyword.get(opts, :manifest_url), 1) do
      :ok
    else
      _invalid -> {:error, :application_catalog_unavailable}
    end
  end

  defp valid_path?(value), do: is_binary(value) and String.starts_with?(value, "/")
  defp valid_text?(value), do: is_binary(value) and value != ""
end
