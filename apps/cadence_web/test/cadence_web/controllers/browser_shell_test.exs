defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: false

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  setup do
    previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])

    Application.put_env(:cadence, :bootstrap_admin,
      enabled: true,
      user_id: "user_bootstrap_admin",
      email: @bootstrap_admin_email,
      display_name: "Bootstrap Admin",
      password: @bootstrap_admin_password,
      session_ttl_seconds: 3600
    )

    assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

    on_exit(fn ->
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
    end)

    :ok
  end

  test "unauthenticated root redirects to sign-in", %{conn: conn} do
    conn = get(conn, "/")

    assert redirected_to(conn) == "/sign-in"
    assert get_session(conn, :user_return_to) == "/"
  end

  test "authenticated root redirects to the operator route", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(conn) == "/operator"
  end

  test "bootstrap admin can establish a browser session and reach operator home", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "bootstrap_admin_session" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    assert redirected_to(conn) == "/operator"

    conn =
      conn
      |> recycle()
      |> get("/operator")

    response = html_response(conn, 200)

    assert response =~ "operator-home"
    assert response =~ "Bootstrap Admin"
    assert response =~ @bootstrap_admin_email
  end

  test "invalid bootstrap credentials keep the user on the sign-in page", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "bootstrap_admin_session" => %{
          "email" => @bootstrap_admin_email,
          "password" => "definitely-wrong"
        }
      })

    response = html_response(conn, 422)

    assert response =~ "bootstrap-admin-sign-in-form"
    assert response =~ "The supplied email or password was rejected."
  end

  test "logout revokes the issued bootstrap session token", %{conn: conn} do
    session_token = bootstrap_admin_session_token()

    conn =
      conn
      |> init_test_session(%{user_session_token: session_token})
      |> delete("/session")

    assert redirected_to(conn) == "/sign-in"

    copied_conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/operator")

    assert redirected_to(copied_conn) == "/sign-in"
    assert {:error, :unauthenticated} = Cadence.authenticate_api_token(session_token)
  end

  test "malformed bootstrap_admin_session params re-render the sign-in form", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "bootstrap_admin_session" => "malformed"
      })

    response = html_response(conn, 422)

    assert response =~ "bootstrap-admin-sign-in-form"
    assert response =~ "Submit a valid bootstrap admin sign-in form."
  end

  defp bootstrap_admin_session_token do
    assert {:ok, issued_session} =
             Cadence.login_bootstrap_admin(@bootstrap_admin_email, @bootstrap_admin_password)

    issued_session.session_token
  end
end
