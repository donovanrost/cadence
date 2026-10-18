defmodule CadenceWeb.PlatformAdministrationPage do
  @moduledoc "Compiled platform administration placement and finite visit-pinned actions."
  import Phoenix.Component

  alias Cadence.Administration.{
    OrganizationCreation,
    OrganizationInvitations,
    ServiceIdentityIssuance
  }

  alias Cadence.Reads.Administration.{OrganizationDetail, OrganizationDirectory, PlatformOverview}

  @pages %{
    "/admin" => "platform_overview",
    "/admin/organizations" => "organization_directory",
    "/admin/organizations/new" => "organization_create",
    "/admin/organizations/:org_id" => "organization_detail",
    "/admin/organizations/:org_id/invite" => "organization_invite"
  }
  @action_routes %{
    "create" => "/admin/organizations/new",
    "issue_service_identity" => "/admin/organizations/:org_id",
    "invite" => "/admin/organizations/:org_id/invite"
  }
  def action_route?(route, event), do: Map.get(@action_routes, event) == route

  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@pages, route) do
    scope = socket.assigns.current_scope
    user_id = scope.user.user_id

    organization_id =
      if route in ["/admin/organizations/:org_id", "/admin/organizations/:org_id/invite"],
        do: Map.get(params, "org_id"),
        else: nil

    session =
      case socket.assigns[:platform_administration_session] do
        %{path: ^path, user_id: ^user_id, organization_id: ^organization_id} = existing ->
          existing

        _ ->
          %{
            path: path,
            route: route,
            user_id: user_id,
            organization_id: organization_id,
            token: Ecto.UUID.generate(),
            consumed?: false,
            created: nil,
            issued_identity: nil,
            submitted: nil
          }
      end

    envelope = %{
      version: 1,
      page: Map.fetch!(@pages, route),
      user_id: user_id,
      organization_id: organization_id,
      action_token: session.token
    }

    page =
      case read(scope, route, params, session) do
        {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
        _ -> Map.put(envelope, :status, "unavailable")
      end

    assign(socket, platform_administration_page: page, platform_administration_session: session)
  end

  def prepare(socket, _, _),
    do: assign(socket, platform_administration_page: nil, platform_administration_session: nil)

  def matches?(socket, token) when is_binary(token) do
    case socket.assigns[:platform_administration_session] do
      %{token: ^token, path: path, user_id: user_id, consumed?: false} ->
        path == socket.assigns.host_path and user_id == socket.assigns.current_scope.user.user_id

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, event, input) do
    session = socket.assigns.platform_administration_session

    if action_route?(session.route, event),
      do: execute(socket, event, input),
      else: {%{status: "unavailable"}, socket}
  end

  defp execute(socket, "create", input) do
    case OrganizationCreation.create(socket.assigns.current_scope, input) do
      {:ok, organization} ->
        completed(socket, :created, organization, %{status: "created", organization: organization})

      result ->
        failed(socket, result)
    end
  end

  defp execute(socket, "issue_service_identity", input) do
    case ServiceIdentityIssuance.issue(
           socket.assigns.current_scope,
           socket.assigns.platform_administration_session.organization_id,
           input
         ) do
      {:ok, identity} ->
        completed(socket, :issued_identity, Map.take(identity, ~w(id name)), %{
          status: "issued",
          identity: identity
        })

      result ->
        failed(socket, result)
    end
  end

  defp execute(socket, "invite", input) do
    case OrganizationInvitations.create(
           socket.assigns.current_scope,
           socket.assigns.platform_administration_session.organization_id,
           input
         ) do
      {:ok, invitation} ->
        completed(socket, :submitted, invitation, %{status: "invited", invitation: invitation})

      result ->
        failed(socket, result)
    end
  end

  defp completed(socket, field, safe_receipt, result) do
    session =
      socket.assigns.platform_administration_session
      |> Map.put(:consumed?, true)
      |> Map.put(field, safe_receipt)

    {result, assign(socket, platform_administration_session: session)}
  end

  defp failed(socket, {:invalid, errors}), do: {%{status: "invalid", errors: errors}, socket}
  defp failed(socket, _), do: {%{status: "unavailable"}, socket}

  defp read(scope, route, params, session) do
    case route do
      "/admin" ->
        PlatformOverview.load(scope)

      "/admin/organizations" ->
        OrganizationDirectory.load(scope, Map.take(params, ~w(after_slug after_id)))

      "/admin/organizations/new" ->
        with {:ok, data} <- OrganizationCreation.load(scope),
             do: {:ok, Map.put(data, "created", session.created)}

      "/admin/organizations/:org_id" ->
        with {:ok, data} <-
               OrganizationDetail.load(
                 scope,
                 session.organization_id,
                 Map.take(params, ~w(members_after invitations_after services_after))
               ),
             do: {:ok, Map.put(data, "issued_identity", session.issued_identity)}

      "/admin/organizations/:org_id/invite" ->
        with {:ok, data} <- OrganizationInvitations.load(scope, session.organization_id),
             do: {:ok, Map.put(data, "submitted", session.submitted)}
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
