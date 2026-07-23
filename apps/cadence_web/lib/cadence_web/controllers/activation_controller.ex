defmodule CadenceWeb.ActivationController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

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
         {:ok, {binding_set_id, version, opts}} <-
           ControlPlaneParams.activation(mission_id, activation_params),
         {:ok, %BindingSetActivation{} = activation} <-
           Cadence.Control.Activations.activate_binding_set(
             organization_id,
             mission_id,
             binding_set_id,
             version,
             opts
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.activation(activation)})
    end
  end

  def show(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %BindingSetActivation{} = activation} <-
           Cadence.Activations.fetch_active_activation(organization_id, mission_id),
         {:ok, %BindingSet{} = binding_set} <-
           Cadence.Activations.fetch_active_binding_set(organization_id, mission_id) do
      json(conn, %{data: ControlPlaneJSON.active_binding_set(activation, binding_set)})
    end
  end
end
