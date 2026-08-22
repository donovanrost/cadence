defmodule CadenceWeb.ActivationController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Management.Activations.{ActivationDecision, ActivationRequest}
  alias Cadence.MissionModels
  alias CadenceWeb.{ActivationJSON, ActivationParams, ControlPlaneAccess}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ActivationParams.filters(params),
         {:ok, requests} <-
           ManagementActivations.list(conn.assigns.current_scope, mission_id, filters) do
      json(conn, %{data: Enum.map(requests, &ActivationJSON.request/1)})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "activation" => activation_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, request_params} <- ActivationParams.request(activation_params),
         {:ok, %ActivationRequest{} = request} <-
           MissionModels.request_promotion(
             conn.assigns.current_scope,
             mission_id,
             request_params.mission_model_revision_id,
             request_params.binding_set_id,
             request_params.version,
             metadata: request_params.metadata
           ) do
      respond_to_request(conn, request)
    end
  end

  def show_request(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "activation_request_id" => activation_request_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ActivationRequest{} = request} <-
           fetch_scoped_request(
             conn.assigns.current_scope,
             mission_id,
             activation_request_id
           ) do
      json(conn, %{data: ActivationJSON.request_result(request, fetch_execution(request))})
    end
  end

  def approve(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "activation_request_id" => activation_request_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ActivationRequest{}} <-
           fetch_scoped_request(
             conn.assigns.current_scope,
             mission_id,
             activation_request_id
           ),
         {:ok, reason} <- ActivationParams.decision(Map.get(params, "decision", %{})),
         {:ok, %ActivationRequest{} = request, %ActivationDecision{} = decision, approved} <-
           ManagementActivations.approve(
             conn.assigns.current_scope,
             activation_request_id,
             reason
           ),
         {:ok, %ActivationExecution{} = execution} <- ControlActivations.execute(approved) do
      json(conn, %{data: ActivationJSON.approval_result(request, decision, execution)})
    end
  end

  def reject(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "activation_request_id" => activation_request_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ActivationRequest{}} <-
           fetch_scoped_request(
             conn.assigns.current_scope,
             mission_id,
             activation_request_id
           ),
         {:ok, reason} <- ActivationParams.decision(Map.get(params, "decision", %{})),
         {:ok, %ActivationRequest{} = request, %ActivationDecision{} = decision} <-
           ManagementActivations.reject(
             conn.assigns.current_scope,
             activation_request_id,
             reason
           ) do
      json(conn, %{data: ActivationJSON.rejection_result(request, decision)})
    end
  end

  def show(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, activation} <- ControlActivations.fetch_active_basis(organization_id, mission_id),
         {:ok, %BindingSet{} = binding_set} <-
           Cadence.Governance.fetch_binding_set(
             organization_id,
             mission_id,
             activation.binding_set_id,
             activation.binding_set_version
           ) do
      json(conn, %{data: ActivationJSON.active_binding_set(activation, binding_set)})
    end
  end

  defp respond_to_request(conn, %ActivationRequest{state: :approval_pending} = request) do
    conn
    |> put_status(:accepted)
    |> json(%{data: ActivationJSON.request_result(request, nil)})
  end

  defp respond_to_request(conn, %ActivationRequest{state: :approved} = request) do
    with {:ok, approved} <- ManagementActivations.fetch_approved(request.activation_request_id),
         {:ok, %ActivationExecution{} = execution} <- ControlActivations.execute(approved) do
      conn
      |> put_status(:created)
      |> json(%{data: ActivationJSON.request_result(request, execution)})
    end
  end

  defp fetch_scoped_request(current_scope, mission_id, activation_request_id) do
    case ManagementActivations.fetch(current_scope, activation_request_id) do
      {:ok, %ActivationRequest{mission_id: ^mission_id} = request} -> {:ok, request}
      {:ok, %ActivationRequest{}} -> {:error, :activation_request_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_execution(%ActivationRequest{} = request) do
    case ControlActivations.fetch_execution(request.activation_request_id) do
      {:ok, %ActivationExecution{} = execution} -> execution
      {:error, :activation_execution_not_found} -> nil
    end
  end
end
