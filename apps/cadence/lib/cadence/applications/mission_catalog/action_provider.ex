defmodule Cadence.Applications.MissionCatalog.ActionProvider do
  @moduledoc "Mission Catalog action authority; upload actions stay at the LiveView boundary."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.ActionContractLedger
  alias Cadence.Applications.{ActionRequest, ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.Reimport
  alias Cadence.Ids
  alias Cadence.Missions.Creation

  @application_key "mission_catalog"
  @surface_action_bindings [
    {"mission_new", 1, "validate"},
    {"mission_new", 1, "save"},
    {"mission_applications", 1, "install"},
    {"mission_applications", 1, "disable"},
    {"mission_applications", 1, "uninstall"},
    {"catalog_database_new", 1, "validate"},
    {"catalog_database_new", 1, "save"},
    {"catalog_database_new", 1, "cancel-upload"},
    {"catalog_database_show", 1, "toggle-revision-form"},
    {"catalog_database_show", 1, "validate"},
    {"catalog_database_show", 1, "save"},
    {"catalog_database_show", 1, "cancel-upload"},
    {"catalog_artifact_show", 1, "reimport"}
  ]

  @impl true
  def application_key, do: @application_key

  @doc "Lifecycle actions target the application key carried by the card input."
  def handles_lifecycle_actions?, do: true

  @doc "Returns the frozen provider-owned surface/action binding ledger."
  @spec surface_action_bindings() :: [{binary(), pos_integer(), binary()}]
  def surface_action_bindings, do: @surface_action_bindings

  @doc "Validates that every binding row is unique and well formed."
  @spec validate_bindings(list()) :: :ok | {:error, atom()}
  def validate_bindings(bindings) when is_list(bindings) do
    valid? =
      Enum.all?(bindings, fn
        {surface_id, surface_version, action_id} ->
          is_binary(surface_id) and surface_id != "" and
            is_integer(surface_version) and surface_version > 0 and
            is_binary(action_id) and action_id != ""

        _other ->
          false
      end)

    cond do
      not valid? -> {:error, :invalid_action_bindings}
      length(bindings) != length(Enum.uniq(bindings)) -> {:error, :duplicate_action_bindings}
      true -> :ok
    end
  end

  def validate_bindings(_bindings), do: {:error, :invalid_action_bindings}

  @impl true
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    with :ok <- ensure_surface_binding(request) do
      execute_action(scope, host_context, request)
    end
  end

  defp execute_action(
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
        {:error, :invalid_application_action_request}
    end
  end

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :invalid_application_action_request}

  defp ensure_surface_binding(%ActionRequest{} = request),
    do: ActionContractLedger.admit(request, __MODULE__)

  defp validate_mission(params), do: creation_result(Creation.validate(params))

  defp save_mission(
         %Scope{organization_id: organization_id} = scope,
         %HostContext{placement: :organization, organization_id: organization_id},
         params
       )
       when is_binary(organization_id),
       do: creation_result(Creation.create(scope, params))

  defp save_mission(_scope, _host_context, _params),
    do: {:error, :unsupported_application_host_context}

  defp creation_result({:error, errors}) when is_map(errors) and not is_struct(errors),
    do: {:error, :invalid_application_action_request}

  defp creation_result(result), do: result

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
    with {:ok, artifact_id} <- application_key(artifact_id) do
      Reimport.execute(scope, mission_id, artifact_id)
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

  defp application_key(value) when is_binary(value) do
    case Ids.path_segment(value) do
      {:ok, value} -> {:ok, value}
      {:error, :invalid_identifier} -> {:error, :invalid_application_action_request}
    end
  end

  defp application_key(_value), do: {:error, :invalid_application_action_request}
end
