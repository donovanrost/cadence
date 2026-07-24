defmodule CadenceWeb.LinkAssignmentController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.CommsJSON, as: CommsJSON

  alias CadenceWeb.API.CommsParams, as: CommsParams

  alias Cadence.Contacts.LinkAssignment
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      link_assignments =
        Cadence.Contacts.list_link_assignments(organization_id, mission_id)
        |> filter_link_assignments(params)
        |> Enum.map(&CommsJSON.link_assignment/1)

      json(conn, %{data: link_assignments})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "link_assignment" => link_assignment_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %LinkAssignment{} = link_assignment} <-
           CommsParams.link_assignment(
             organization_id,
             mission_id,
             link_assignment_params
           ),
         {:ok, %LinkAssignment{} = persisted_link_assignment} <-
           Cadence.Contacts.persist_link_assignment(organization_id, link_assignment) do
      conn
      |> put_status(:created)
      |> json(%{data: CommsJSON.link_assignment(persisted_link_assignment)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "link_assignment_id" => link_assignment_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %LinkAssignment{} = link_assignment} <-
           Cadence.Contacts.fetch_link_assignment(organization_id, mission_id, link_assignment_id) do
      json(conn, %{data: CommsJSON.link_assignment(link_assignment)})
    end
  end

  def delete(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "link_assignment_id" => link_assignment_id
        } = params
      ) do
    link_assignment_params = Map.get(params, "link_assignment", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, metadata} <-
           CommsParams.link_assignment_delete(link_assignment_params),
         {:ok, %LinkAssignment{} = link_assignment} <-
           Cadence.Contacts.delete_link_assignment(
             organization_id,
             mission_id,
             link_assignment_id,
             metadata
           ) do
      json(conn, %{data: CommsJSON.link_assignment(link_assignment)})
    end
  end

  def apply_template(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "path_template_id" => path_template_id
        } = params
      ) do
    application_params = Map.get(params, "link_template_application", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- CommsParams.link_template_application(application_params),
         {:ok, source_template} <-
           fetch_application_path_template(organization_id, mission_id, path_template_id, attrs),
         {:ok, spacecraft} <- application_spacecraft(organization_id, mission_id, attrs),
         {:ok, result} <-
           Cadence.Contacts.apply_link_template(
             organization_id,
             mission_id,
             source_template,
             spacecraft,
             attrs
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: CommsJSON.link_template_application_result(result)})
    end
  end

  defp filter_link_assignments(link_assignments, params) when is_list(link_assignments) do
    Enum.filter(link_assignments, fn assignment ->
      matches_param?(assignment.spacecraft_id, Map.get(params, "spacecraft_id")) and
        matches_param?(assignment.source_endpoint_ref, Map.get(params, "source_endpoint_ref")) and
        matches_param?(assignment.path_template_id, Map.get(params, "path_template_id"))
    end)
  end

  defp matches_param?(_value, nil), do: true
  defp matches_param?(value, expected), do: value == expected

  defp fetch_application_path_template(organization_id, mission_id, path_template_id, attrs) do
    case attrs["path_template_version"] do
      nil ->
        Cadence.Contacts.fetch_path_template(organization_id, mission_id, path_template_id)

      version ->
        Cadence.Contacts.fetch_path_template_version(
          organization_id,
          mission_id,
          path_template_id,
          version
        )
    end
  end

  defp application_spacecraft(organization_id, mission_id, %{"target_mode" => "selected"} = attrs) do
    spacecraft = Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id)
    spacecraft_by_id = Map.new(spacecraft, &{&1.spacecraft_id, &1})
    spacecraft_ids = attrs["spacecraft_ids"]

    missing_ids = Enum.reject(spacecraft_ids, &Map.has_key?(spacecraft_by_id, &1))

    if missing_ids == [] do
      {:ok, Enum.map(spacecraft_ids, &Map.fetch!(spacecraft_by_id, &1))}
    else
      {:error, {:invalid_param, "spacecraft_ids", {:unknown, missing_ids}}}
    end
  end

  defp application_spacecraft(organization_id, mission_id, attrs) do
    spacecraft =
      organization_id
      |> Cadence.SpacecraftStore.list_spacecraft(mission_id)
      |> filter_spacecraft(attrs["spacecraft_query"])

    {:ok, spacecraft}
  end

  defp filter_spacecraft(spacecraft, nil), do: spacecraft
  defp filter_spacecraft(spacecraft, ""), do: spacecraft

  defp filter_spacecraft(spacecraft, query) when is_binary(query) do
    normalized_query = String.downcase(query)

    Enum.filter(spacecraft, fn spacecraft ->
      spacecraft
      |> spacecraft_search_text()
      |> String.contains?(normalized_query)
    end)
  end

  defp spacecraft_search_text(spacecraft) do
    [
      spacecraft.spacecraft_id,
      spacecraft.display_name,
      if(spacecraft.scid, do: Integer.to_string(spacecraft.scid), else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end
end
