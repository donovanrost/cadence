defmodule Cadence.Administration.ConsoleAdmin do
  @moduledoc """
  Platform administrators' writes for the console admin area (L7), each recorded in the platform
  audit (`PlatformEvents`). Every call first checks `Access.authorize/1` (admin mode, an active
  platform admin), then reuses the organization-scoped function the People page uses, which a
  platform admin passes for any organization.
  """

  alias Cadence.Administration.{
    Access,
    ConsoleOrganizations,
    ConsoleServiceIdentities,
    OrganizationCreation,
    OrganizationInvitations,
    OrganizationPeople,
    PlatformEvents,
    ServiceIdentityAdministration
  }

  alias Cadence.Organizations

  @doc """
  Creates an organization and invites its first administrator. When the organization is created
  but the invitation fails, the result says both (`invitation: nil`, `invitation_error`).
  """
  def create_organization(scope, %{"name" => name, "slug" => slug, "first_admin_email" => email})
      when is_binary(name) and is_binary(slug) and is_binary(email) do
    with {:ok, admin} <- Access.authorize(scope),
         :ok <- email(email),
         {:ok, org} <- create(scope, name, slug) do
      record(admin, "organization_created", org["id"], {"organization", org["id"], org["name"]})

      {invitation, error} =
        case invite(scope, org["id"], email, "organization_admin") do
          {:ok, invitation} ->
            {%{email: invitation["email"], delivery: invitation["delivery"]}, nil}

          {:invalid, errors} ->
            {nil, errors |> Map.values() |> Enum.join(" ")}

          {:error, _reason} ->
            {nil, "The invitation couldn't be sent."}
        end

      {:ok,
       %{
         organization: %{id: org["id"], name: org["name"], slug: org["slug"]},
         invitation: invitation,
         invitation_error: error
       }}
    end
  end

  def create_organization(_scope, _params),
    do: {:invalid, %{"form" => "Enter a name, a slug and the first admin's email."}}

  @doc "Invites someone into any organization (`role`: member | organization_admin)."
  def invite_member(scope, organization_id, %{"email" => email, "role" => role})
      when is_binary(email) and is_binary(role) do
    with {:ok, _admin} <- Access.authorize(scope),
         {:ok, _org} <- Organizations.fetch_organization(organization_id) do
      invite(scope, organization_id, email, role)
    end
  end

  def invite_member(_scope, _organization_id, _params),
    do: {:invalid, %{"form" => "Enter an email and a role."}}

  def withdraw_invitation(scope, organization_id, invitation_id) do
    with {:ok, admin} <- Access.authorize(scope),
         :ok <- OrganizationPeople.revoke_invitation(scope, organization_id, invitation_id) do
      record(admin, "invitation_withdrawn", organization_id, {"invitation", invitation_id, nil})
      {:ok, %{id: invitation_id, state: "withdrawn"}}
    end
  end

  def issue_service_identity(scope, %{"organization_id" => organization_id} = params) do
    input = Map.take(params, ~w(name capability mission_id))

    with {:ok, admin} <- Access.authorize(scope),
         {:ok, issued} <-
           ServiceIdentityAdministration.create(scope, organization_id, people_params(input)) do
      identity = issued.service_identity

      record(
        admin,
        "service_identity_issued",
        organization_id,
        {"service_identity", identity.id, identity.name}
      )

      {:ok, issued}
    end
  end

  def issue_service_identity(_scope, _params),
    do: {:invalid, %{"organization_id" => "is required"}}

  def rotate_service_identity(scope, organization_id, id) do
    with {:ok, admin} <- Access.authorize(scope),
         {:ok, issued} <- ServiceIdentityAdministration.rotate(scope, organization_id, id) do
      record(
        admin,
        "service_identity_rotated",
        organization_id,
        {"service_identity", id, issued.service_identity.name}
      )

      {:ok, issued}
    end
  end

  def revoke_service_identity(scope, organization_id, id) do
    with {:ok, admin} <- Access.authorize(scope),
         # The name is read before the revoke: a revoked identity is no longer listed.
         row = ConsoleServiceIdentities.row(organization_id, id),
         :ok <- ServiceIdentityAdministration.revoke(scope, organization_id, id) do
      record(
        admin,
        "service_identity_revoked",
        organization_id,
        {"service_identity", id, row && row.name}
      )

      {:ok, %{id: id, state: "revoked"}}
    end
  end

  @doc "Admin mode entered or left (the session's own action; the actor is the signed-in user)."
  def record_admin_mode(user_id, :entered, expires_at),
    do:
      PlatformEvents.record(user_id, "admin_mode_entered", %{
        details: %{"expires_at" => expires_at}
      })

  def record_admin_mode(user_id, :left, _expires_at),
    do: PlatformEvents.record(user_id, "admin_mode_left", %{})

  defp create(scope, name, slug) do
    case OrganizationCreation.create(scope, %{"display_name" => name, "slug" => slug}) do
      {:invalid, %{"slug" => message}} ->
        {:invalid,
         %{"slug" => message, "suggestion" => ConsoleOrganizations.suggestion(String.trim(slug))}}

      other ->
        other
    end
  end

  defp invite(scope, organization_id, email, role) do
    input = %{
      "email" => email,
      "display_name" => "",
      "membership_role" => role,
      "grant_platform_admin" => false
    }

    with {:ok, invitation} <- OrganizationInvitations.create(scope, organization_id, input) do
      {:ok, admin} = Access.authorize(scope)

      record(
        admin,
        "invitation_created",
        organization_id,
        {"invitation", invitation["id"], invitation["email"]}
      )

      {:ok, invitation}
    end
  end

  # The People page's create params (O6): name, capability, mission_id.
  defp people_params(input),
    do: %{
      "name" => input["name"],
      "capabilities" => List.wrap(input["capability"]),
      "mission_id" => input["mission_id"]
    }

  defp email(email) do
    email = String.trim(email)

    if byte_size(email) in 3..254 and String.match?(email, ~r/^[^\s@]+@[^\s@]+$/u),
      do: :ok,
      else: {:invalid, %{"first_admin_email" => "Enter a valid email address."}}
  end

  defp record(admin, action, organization_id, target),
    do:
      PlatformEvents.record(admin.user_id, action, %{
        organization_id: organization_id,
        target: target
      })
end
