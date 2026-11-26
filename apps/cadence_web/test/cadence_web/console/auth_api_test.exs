defmodule CadenceWeb.Console.AuthAPITest do
  @moduledoc "L5: console sign-in and invitation links, signed in or out (docs/apogee/api/session.md)."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Accounts
  alias Cadence.Accounts.{AttemptLimit, OrganizationInvitationRow, UserRow}
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    AttemptLimit.reset()
    on_exit(&AttemptLimit.reset/0)
    org = TestFixtures.persist_org!(display_name: "Acme Space")
    inviter = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(inviter, org, role: :organization_admin)
    %{org: org, inviter: inviter}
  end

  defp invite!(c, email) do
    {:ok, %{invitation_token: token, invitation: invitation}} =
      Accounts.establish_organization_access(email, c.org.organization_id,
        membership_role: :member,
        invited_by_user_id: c.inviter.user_id,
        force_invitation: true
      )

    {token, invitation}
  end

  defp email, do: "invitee-#{System.unique_integer([:positive])}@example.com"
  defp link(token), do: "/api/v1/auth/invitations/#{token}"
  defp signed_in?(conn), do: is_binary(get_session(conn, :user_session_token))

  describe "sign-in" do
    test "a right pair starts a fresh session and goes to a safe return_to", c do
      conn =
        build_conn()
        |> post("/api/v1/auth/sign-in", %{
          "email" => c.inviter.email,
          "password" => TestFixtures.default_password(),
          "return_to" => "/console/m/earendil/now?x=1"
        })

      assert %{"data" => %{"redirect_to" => "/console/m/earendil/now?x=1"}} =
               json_response(conn, 200)

      assert signed_in?(conn)
      assert get_session(conn, :current_organization_id) == c.org.organization_id

      session = conn |> recycle() |> get("/api/v1/session") |> json_response(200)
      assert session["data"]["user"]["email"] == c.inviter.email
    end

    test "return_to must be a same-origin relative path", c do
      for target <- [
            "https://evil.example/x",
            "//evil.example/x",
            "/\\evil",
            "/console/sign-in",
            "nope"
          ] do
        conn =
          post(build_conn(), "/api/v1/auth/sign-in", %{
            "email" => c.inviter.email,
            "password" => TestFixtures.default_password(),
            "return_to" => target
          })

        assert json_response(conn, 200)["data"]["redirect_to"] == "/console", target
      end
    end

    test "a wrong password and an unknown email get the same answer; repeats are held back", c do
      for email <- [c.inviter.email, email()] do
        response =
          post(build_conn(), "/api/v1/auth/sign-in", %{
            "email" => email,
            "password" => "wrong-1"
          })

        assert %{"error" => %{"code" => "credentials_incorrect"}} = json_response(response, 422)
        refute signed_in?(response)
      end

      for _ <- 1..6 do
        post(build_conn(), "/api/v1/auth/sign-in", %{
          "email" => c.inviter.email,
          "password" => "wrong-1"
        })
      end

      held =
        post(build_conn(), "/api/v1/auth/sign-in", %{
          "email" => c.inviter.email,
          "password" => TestFixtures.default_password()
        })

      assert %{"error" => %{"code" => "too_many_attempts", "details" => %{"retry_after" => _}}} =
               json_response(held, 429)
    end
  end

  describe "invitation links" do
    test "an unknown token says nothing", _c do
      assert %{"data" => %{"case" => "unknown", "email" => nil, "organization" => nil}} =
               build_conn() |> get(link("not-a-token")) |> json_response(200)
    end

    test "signed out with no account: new_account; accepting creates, joins and signs in", c do
      address = email()
      {token, _invitation} = invite!(c, address)

      assert %{
               "case" => "new_account",
               "email" => ^address,
               "organization" => %{"name" => "Acme Space"},
               "role" => "member",
               "invited_by" => %{"name" => "Mira K."}
             } = build_conn() |> get(link(token)) |> json_response(200) |> Map.fetch!("data")

      assert %{"error" => %{"details" => %{"password" => _}}} =
               build_conn()
               |> post(link(token) <> "/accept", %{
                 "kind" => "new_account",
                 "name" => "Ana",
                 "password" => "short"
               })
               |> json_response(422)

      accepted =
        post(build_conn(), link(token) <> "/accept", %{
          "kind" => "new_account",
          "name" => "Ana",
          "password" => "a-long-new-password"
        })

      assert %{"data" => %{"organization_id" => org_id, "redirect_to" => "/console"}} =
               json_response(accepted, 200)

      assert org_id == c.org.organization_id
      assert signed_in?(accepted)

      assert %{"case" => "used", "email" => nil} =
               build_conn() |> get(link(token)) |> json_response(200) |> Map.fetch!("data")
    end

    test "signed out with an account: existing_account needs its current password", c do
      user = TestFixtures.persist_user!(display_name: "Kept")
      {token, _invitation} = invite!(c, user.email)

      assert build_conn() |> get(link(token)) |> json_response(200) |> get_in(["data", "case"]) ==
               "existing_account"

      assert %{
               "error" => %{
                 "code" => "invitation_case_changed",
                 "details" => %{"case" => "existing_account"}
               }
             } =
               build_conn()
               |> post(link(token) <> "/accept", %{
                 "kind" => "new_account",
                 "name" => "X",
                 "password" => "a-long-new-password"
               })
               |> json_response(409)

      assert %{"error" => %{"code" => "credentials_incorrect"}} =
               build_conn()
               |> post(link(token) <> "/accept", %{
                 "kind" => "existing_account",
                 "password" => "wrong-1"
               })
               |> json_response(422)

      joined =
        post(build_conn(), link(token) <> "/accept", %{
          "kind" => "existing_account",
          "password" => TestFixtures.default_password()
        })

      assert json_response(joined, 200)["data"]["organization_id"] == c.org.organization_id
      assert Repo.get!(UserRow, user.user_id).display_name == "Kept"
    end

    test "signed in: the addressee joins or declines; anyone else is told it's for another account",
         c do
      user = TestFixtures.persist_user!()
      other = TestFixtures.persist_user!()
      {token, invitation} = invite!(c, user.email)

      other_conn = TestFixtures.member_conn(other)

      assert %{"case" => "signed_in_other", "email" => email} =
               other_conn |> get(link(token)) |> json_response(200) |> Map.fetch!("data")

      assert email == user.email

      assert %{"error" => %{"code" => "invitation_for_another_account"}} =
               other_conn |> post(link(token) <> "/accept", %{}) |> json_response(409)

      mine = TestFixtures.member_conn(user)

      assert mine |> get(link(token)) |> json_response(200) |> get_in(["data", "case"]) ==
               "signed_in_match"

      assert mine |> post(link(token) <> "/decline", %{}) |> response(204)

      assert Repo.get!(OrganizationInvitationRow, invitation.organization_invitation_id).status ==
               "declined"

      assert %{
               "error" => %{
                 "code" => "invitation_unavailable",
                 "details" => %{"case" => "declined"}
               }
             } =
               mine |> post(link(token) <> "/accept", %{}) |> json_response(409)
    end

    test "signed in as the addressee, accepting joins without a password", c do
      user = TestFixtures.persist_user!()
      {token, _invitation} = invite!(c, user.email)

      assert %{"data" => %{"organization_id" => org_id}} =
               user
               |> TestFixtures.member_conn()
               |> post(link(token) <> "/accept", %{"kind" => "signed_in_match"})
               |> json_response(200)

      assert org_id == c.org.organization_id
      assert {:ok, _} = Accounts.fetch_user_membership(user.user_id, org_id)
    end
  end

  test "the auth screens are served without a session", _c do
    for path <- [
          "/console/sign-in",
          "/console/invitations/some-token",
          "/console/no-organization"
        ] do
      response = get(build_conn(), path)
      refute response.status in [301, 302], path
    end
  end
end
