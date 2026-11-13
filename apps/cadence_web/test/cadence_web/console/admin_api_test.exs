defmodule CadenceWeb.Console.AdminAPITest do
  @moduledoc "L7 platform admin area (docs/apogee/api/admin.md)."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Administration.PlatformEvents
  alias CadenceWeb.TestFixtures

  setup do
    admin =
      TestFixtures.persist_user!(display_name: "Pat Platform", capabilities: [:platform_admin])

    org = TestFixtures.persist_org!(display_name: "Acme Space")
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(member, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, display_name: "Earendil")
    %{admin: admin, org: org, member: member, mission: mission}
  end

  defp admin_conn(c) do
    c.admin
    |> TestFixtures.member_conn()
    |> Plug.Test.init_test_session(%{admin_mode_expires_at: System.system_time(:second) + 600})
  end

  defp api(path), do: "/api/console/v1/admin" <> path

  @row_keys ~w(capabilities created_at created_by id last_used_at mission name organization)

  test "only a platform admin in admin mode gets in", c do
    for conn <- [TestFixtures.member_conn(c.member), TestFixtures.member_conn(c.admin)] do
      assert %{"error" => %{"code" => "admin_mode_required"}} =
               conn |> get(api("/organizations")) |> json_response(403)
    end
  end

  test "AD1: list with counts, slug check, create and invite the first admin", c do
    data =
      c
      |> admin_conn()
      |> get(api("/organizations?q=acme"))
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"name" => "Acme Space", "members" => 1, "missions" => 1, "created_by" => nil} = row] =
             data["organizations"]

    assert is_binary(row["created_at"])

    taken =
      c
      |> admin_conn()
      |> get(api("/organizations/slug?slug=#{c.org.slug}"))
      |> json_response(200)

    assert %{"available" => false, "suggestion" => suggestion} = taken["data"]
    assert suggestion == c.org.slug <> "-2"

    created =
      c
      |> admin_conn()
      |> post(api("/organizations"), %{
        "name" => "Nova",
        "slug" => "nova-#{System.unique_integer([:positive])}",
        "first_admin_email" => "first@example.com"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{
             "organization" => %{"id" => new_id, "name" => "Nova"},
             "invitation" => %{"email" => "first@example.com"},
             "invitation_error" => nil
           } = created

    listed = c |> admin_conn() |> get(api("/organizations?q=Nova")) |> json_response(200)

    assert [%{"id" => ^new_id, "created_by" => %{"name" => "Pat Platform"}}] =
             listed["data"]["organizations"]

    assert %{
             "error" => %{
               "code" => "invalid_params",
               "details" => %{"slug" => _, "suggestion" => _}
             }
           } =
             c
             |> admin_conn()
             |> post(api("/organizations"), %{
               "name" => "Dup",
               "slug" => c.org.slug,
               "first_admin_email" => "x@example.com"
             })
             |> json_response(422)
  end

  test "AD2: one organization; invite and withdraw across organizations", c do
    path = api("/organizations/#{c.org.organization_id}")
    data = c |> admin_conn() |> get(path) |> json_response(200) |> Map.fetch!("data")

    assert [%{"name" => "Mira K.", "role" => "organization_admin"}] = data["members"]
    assert [%{"name" => "Earendil"}] = data["missions"]
    assert data["invitations"] == []

    assert %{"data" => %{"id" => invitation_id}} =
             c
             |> admin_conn()
             |> post(path <> "/invitations", %{"email" => "ana@example.com", "role" => "member"})
             |> json_response(201)

    assert [
             %{
               "email" => "ana@example.com",
               "state" => "pending",
               "invited_by" => %{"name" => "Pat Platform"}
             }
           ] =
             c
             |> admin_conn()
             |> get(path)
             |> json_response(200)
             |> get_in(["data", "invitations"])

    assert %{"data" => %{"state" => "withdrawn"}} =
             c
             |> admin_conn()
             |> delete(path <> "/invitations/#{invitation_id}")
             |> json_response(200)

    assert c |> admin_conn() |> get(api("/organizations/org-nope")) |> json_response(404)
  end

  test "AD3: issue (token once), list in words, rotate, revoke", c do
    issued =
      c
      |> admin_conn()
      |> post(api("/service-identities"), %{
        "organization_id" => c.org.organization_id,
        "name" => "Ingest bot",
        "capability" => "mission_admin",
        "mission_id" => c.mission.mission_id
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{
             "token" => token,
             "service_identity" => %{
               "id" => id,
               "capabilities" => [%{"key" => "mission_admin", "label" => label}]
             }
           } = issued

    assert is_binary(token) and label =~ "Mission admin"

    listed =
      c
      |> admin_conn()
      |> get(api("/service-identities?organization_id=#{c.org.organization_id}"))
      |> json_response(200)

    assert [
             %{
               "id" => ^id,
               "mission" => %{"name" => "Earendil"},
               "created_by" => %{"name" => "Pat Platform"}
             } = row
           ] = listed["data"]["service_identities"]

    refute Map.has_key?(row, "token")
    assert length(listed["data"]["capabilities"]) == 2

    # Issue answers with the list row (AD3), so the console decodes it and shows the token.
    assert Map.keys(row) |> Enum.sort() == @row_keys
    assert issued["service_identity"] == row
    assert %{"organization" => %{"id" => _, "name" => "Acme Space"}, "last_used_at" => nil} = row

    rotated_conn =
      c
      |> admin_conn()
      |> post(api("/service-identities/#{id}/rotate"), %{
        "organization_id" => c.org.organization_id
      })

    rotated = json_response(rotated_conn, 200)

    assert rotated["data"]["token"] != token
    assert get_resp_header(rotated_conn, "cache-control") == ["no-store"]
    assert Map.keys(rotated["data"]) |> Enum.sort() == ["service_identity", "token"]
    assert rotated["data"]["service_identity"] == row

    assert %{"data" => %{"state" => "revoked"}} =
             c
             |> admin_conn()
             |> delete(api("/service-identities/#{id}?organization_id=#{c.org.organization_id}"))
             |> json_response(200)

    assert %{"error" => %{"code" => "invalid_params"}} =
             c
             |> admin_conn()
             |> post(api("/service-identities"), %{
               "organization_id" => c.org.organization_id,
               "name" => "x",
               "capability" => "mission_admin"
             })
             |> json_response(422)
  end

  test "audit targets always carry a label: the name, else the id", c do
    %{"data" => %{"service_identity" => %{"id" => id}}} =
      c
      |> admin_conn()
      |> post(api("/service-identities"), %{
        "organization_id" => c.org.organization_id,
        "name" => "Relay bot",
        "capability" => "organization_admin"
      })
      |> json_response(201)

    c
    |> admin_conn()
    |> delete(api("/service-identities/#{id}?organization_id=#{c.org.organization_id}"))
    |> json_response(200)

    # A withdrawal (and any revoke recorded before the name was) has no name on record.
    :ok =
      PlatformEvents.record(c.admin.user_id, "invitation_withdrawn", %{
        organization_id: c.org.organization_id,
        target: {"invitation", "inv_unnamed", nil}
      })

    events =
      c |> admin_conn() |> get(api("/audit")) |> json_response(200) |> get_in(["data", "events"])

    for %{"target" => target} <- events, target != nil do
      assert %{"kind" => kind, "id" => target_id, "label" => label} = target
      assert is_binary(kind) and is_binary(target_id) and is_binary(label)
    end

    assert Enum.any?(
             events,
             &match?(
               %{
                 "action" => "Revoked service identity Relay bot in Acme Space",
                 "target" => %{"id" => ^id, "label" => "Relay bot"}
               },
               &1
             )
           )

    assert Enum.any?(
             events,
             &match?(%{"target" => %{"id" => "inv_unnamed", "label" => "inv_unnamed"}}, &1)
           )
  end

  test "AD4: every mission with what this node knows", c do
    data = c |> admin_conn() |> get(api("/runtime")) |> json_response(200) |> Map.fetch!("data")
    row = Enum.find(data["missions"], &(&1["mission"]["id"] == c.mission.mission_id))

    assert %{
             "organization" => %{"name" => "Acme Space"},
             "runtime" => nil,
             "telemetry_last_received_at" => nil,
             "technical" => []
           } = row
  end

  test "the platform audit records admin actions and admin mode, without secrets", c do
    conn = TestFixtures.member_conn(c.admin)

    entered =
      post(conn, "/api/console/v1/session/admin-mode", %{
        "password" => TestFixtures.default_password()
      })

    assert json_response(entered, 200)

    entered
    |> recycle()
    |> post(api("/service-identities"), %{
      "organization_id" => c.org.organization_id,
      "name" => "Bot",
      "capability" => "organization_admin"
    })
    |> json_response(201)

    left = entered |> recycle() |> delete("/api/console/v1/session/admin-mode")
    assert response(left, 204)

    body = c |> admin_conn() |> get(api("/audit")) |> response(200)
    actions = body |> Jason.decode!() |> get_in(["data", "events"]) |> Enum.map(& &1["action"])

    assert "Left admin mode" in actions
    assert "Issued service identity Bot in Acme Space" in actions
    assert Enum.any?(actions, &String.starts_with?(&1, "Entered admin mode (until "))
    refute body =~ TestFixtures.default_password()

    org_audit =
      c.member
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{c.org.organization_id}/audit?kinds=platform")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert [%{"kind" => "platform", "action" => "Issued service identity Bot in Acme Space"}] =
             org_audit
  end
end
