defmodule Cadence.Applications.MissionCatalog.ActionProvider do
  @moduledoc "Mission Catalog action authority; upload actions stay at the LiveView boundary."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Ids
  alias Cadence.Missions
  alias Cadence.Missions.Mission

  @application_key "mission_catalog"

  @impl true
  def application_key, do: @application_key

  @doc "Lifecycle actions target the application key carried by the card input."
  def handles_lifecycle_actions?, do: true

  @impl true
  def execute(
        %Scope{} = scope,
        %HostContext{} = host_context,
        %ActionRequest{action_id: action_id, params: params}
      )
      when is_map(params) do
    case action_id do
      "validate" ->
        validate_mission(params)

      "save" ->
        save_mission(scope, host_context, params)

      action_id when action_id in ["install", "disable", "uninstall"] ->
        lifecycle(scope, host_context, action_id, params)

      action_id when action_id in ["toggle-revision-form", "cancel-upload"] ->
        {:error, :mission_catalog_local_upload_boundary}

      "reimport" ->
        reimport(scope, host_context, params)

      _other ->
        {:error, :unsupported_application_action}
    end
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :invalid_application_action_request}

  defp validate_mission(%{"mission" => params}) when is_map(params) do
    with {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, slug} <- required_text(params, "slug"),
         {:ok, slug} <- valid_slug(slug) do
      {:ok, %{"mission" => %{"display_name" => display_name, "slug" => slug}}}
    end
  end

  defp validate_mission(_params), do: {:error, :invalid_application_action_request}

  defp save_mission(
         %Scope{organization_id: organization_id},
         %HostContext{placement: :organization, organization_id: organization_id},
         %{"mission" => params}
       )
       when is_map(params) and is_binary(organization_id) do
    with {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, slug} <- required_text(params, "slug"),
         {:ok, slug} <- valid_slug(slug),
         {:ok, mission} <-
           Missions.persist_mission(%Mission{
             mission_id: Ids.new("mission"),
             organization_id: organization_id,
             display_name: display_name,
             slug: slug
           }) do
      {:ok,
       %{
         "mission" => %{
           "id" => mission.mission_id,
           "display_name" => mission.display_name,
           "slug" => mission.slug,
           "href" => "/missions/#{mission.mission_id}"
         }
       }}
    end
  end

  defp save_mission(_scope, _host_context, _params),
    do: {:error, :unsupported_application_host_context}

  defp lifecycle(scope, host_context, "install", %{"key" => application_key}) do
    with {:ok, application_key} <- application_key(application_key),
         {:ok, installation} <-
           ApplicationInstallations.install(scope, host_context, application_key) do
      {:ok, installation_result(installation)}
    end
  end

  defp lifecycle(scope, host_context, "disable", %{"key" => application_key}) do
    with {:ok, application_key} <- application_key(application_key),
         {:ok, installation} <-
           ApplicationInstallations.disable(scope, host_context, application_key) do
      {:ok, installation_result(installation)}
    end
  end

  defp lifecycle(scope, host_context, "uninstall", %{"key" => application_key}) do
    with {:ok, application_key} <- application_key(application_key),
         {:ok, installation} <-
           ApplicationInstallations.uninstall(scope, host_context, application_key) do
      {:ok, installation_result(installation)}
    end
  end

  defp lifecycle(_scope, _host_context, _action_id, _params),
    do: {:error, :invalid_application_action_request}

  defp reimport(scope, %HostContext{placement: :mission, mission_id: mission_id}, %{
         "artifact_id" => artifact_id
       }) do
    with {:ok, artifact_id} <- application_key(artifact_id),
         {:ok, artifact} <- Catalog.fetch_artifact(scope.organization_id, mission_id, artifact_id),
         {:ok, run} <-
           Catalog.start_import_run(
             scope.organization_id,
             mission_id,
             artifact.artifact_id,
             artifact.format_key,
             requested_by: actor(scope)
           ) do
      {:ok,
       %{
         "import_run_id" => run.import_run_id,
         "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
       }}
    end
  end

  defp reimport(_scope, _host_context, _params),
    do: {:error, :mission_catalog_local_upload_boundary}

  defp installation_result(installation) do
    %{
      "application_key" => installation.application_key,
      "application_version" => installation.application_version,
      "lifecycle_state" => Atom.to_string(installation.lifecycle_state)
    }
  end

  defp actor(%Scope{user: %{id: id, email: email}}), do: %{user_id: id, email: email}
  defp actor(%Scope{}), do: %{}

  defp application_key(value) when is_binary(value) do
    case Ids.path_segment(value) do
      {:ok, value} -> {:ok, value}
      {:error, :invalid_identifier} -> {:error, :invalid_application_action_request}
    end
  end

  defp application_key(_value), do: {:error, :invalid_application_action_request}

  defp required_text(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, String.trim(value)}
      _invalid -> {:error, :invalid_application_action_request}
    end
  end

  defp valid_slug(slug) do
    if Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, slug),
      do: {:ok, slug},
      else: {:error, :invalid_application_action_request}
  end
end
