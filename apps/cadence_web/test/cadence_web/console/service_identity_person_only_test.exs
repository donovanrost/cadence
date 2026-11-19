defmodule CadenceWeb.Console.ServiceIdentityPersonOnlyTest do
  @moduledoc """
  #281, ux U104: the console's service identity actions answer a service identity's scope with
  403 `authenticated_user_required` in each act's words. Over HTTP the organization scope refuses
  a service first, so these call the controllers directly: they pin the backstop's answer.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
  alias CadenceWeb.Console.{PeopleController, ServiceIdentityController}
  alias CadenceWeb.TestFixtures

  setup %{conn: conn} do
    org = TestFixtures.persist_org!()

    {:ok, %{service_identity: target, api_token: token}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: org.organization_id,
          display_name: "Automation",
          capabilities: [:organization_admin]
        })
      )

    {:ok, service} = Auth.authenticate_api_token(token)

    %{
      conn: Plug.Conn.assign(conn, :current_scope, service),
      org: org.organization_id,
      target: target.service_identity_id
    }
  end

  test "create", c do
    body =
      c.conn
      |> ServiceIdentityController.create(%{
        "organization_id" => c.org,
        "name" => "Minted",
        "capabilities" => ["organization_admin"]
      })
      |> refused()

    assert body["message"] =~ "Not created: only a person can create a service identity"
    refute Map.has_key?(body, "details")
  end

  test "rotate", c do
    params = %{"organization_id" => c.org, "service_identity_id" => c.target}

    assert refused(ServiceIdentityController.rotate(c.conn, params))["message"] =~
             "Not rotated: only a person can rotate a service identity's key"
  end

  test "revoke", c do
    params = %{"organization_id" => c.org, "service_identity_id" => c.target}

    assert refused(ServiceIdentityController.revoke(c.conn, params))["message"] =~
             "Not revoked: only a person can revoke a service identity"
  end

  test "list", c do
    assert refused(PeopleController.service_identities(c.conn, %{"organization_id" => c.org})) ==
             %{
               "code" => "authenticated_user_required",
               "message" =>
                 "Only a person can list the organization's service identities, not a service identity."
             }
  end

  defp refused(conn) do
    assert %{"error" => %{"code" => "authenticated_user_required"} = error} =
             json_response(conn, 403)

    error
  end
end
