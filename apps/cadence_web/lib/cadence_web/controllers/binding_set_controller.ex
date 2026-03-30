defmodule CadenceWeb.BindingSetController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.ApplicationDispatch.BindingSet
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "binding_set" => binding_set_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %BindingSet{} = binding_set} <-
           ControlPlaneParams.binding_set(organization_id, mission_id, binding_set_params),
         {:ok, %BindingSet{} = persisted_binding_set} <-
           Cadence.persist_binding_set(organization_id, binding_set),
         {:ok, %BindingSet{} = hydrated_binding_set} <-
           Cadence.fetch_binding_set(
             organization_id,
             mission_id,
             persisted_binding_set.binding_set_id,
             persisted_binding_set.version
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.binding_set(hydrated_binding_set)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "binding_set_id" => binding_set_id,
        "version" => version
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {version, ""} <- Integer.parse(version),
         {:ok, %BindingSet{} = binding_set} <-
           Cadence.fetch_binding_set(organization_id, mission_id, binding_set_id, version) do
      json(conn, %{data: ControlPlaneJSON.binding_set(binding_set)})
    else
      :error -> {:error, {:invalid_param, "version", :integer}}
      {:error, reason} -> {:error, reason}
    end
  end
end
