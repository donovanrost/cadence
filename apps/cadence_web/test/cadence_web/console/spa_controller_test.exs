defmodule CadenceWeb.Console.SPAControllerTest do
  # Mutates the :console application env, so it cannot run concurrently.
  use CadenceWeb.ConnCase, async: false
  @moduletag :tmp_dir

  alias CadenceWeb.Console.Shell
  alias CadenceWeb.TestFixtures

  @index """
  <!doctype html>
  <html><head><title>Cadence</title><script type="module" src="/console/assets/index-abc.js"></script></head>
  <body><div id="app"></div></body></html>
  """

  setup %{tmp_dir: dir} do
    previous = Application.get_env(:cadence_web, :console)
    index_path = Path.join(dir, "index.html")
    File.write!(index_path, @index)
    Application.put_env(:cadence_web, :console, index_path: index_path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence_web, :console, previous),
        else: Application.delete_env(:cadence_web, :console)
    end)

    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)

    %{user: user, index_path: index_path}
  end

  test "redirects an unauthenticated visitor to sign-in and remembers the path", %{conn: conn} do
    conn = get(conn, "/console/missions/m1/now?tab=alarms")

    # One hop: straight to the console's own sign-in, with the target remembered.
    assert redirected_to(conn) == "/console/sign-in"
    assert get_session(conn, :user_return_to) == "/console/missions/m1/now?tab=alarms"
  end

  test "serves the built index with the CSRF token injected for any client route", c do
    for path <- ["/console", "/console/", "/console/missions/m1/now"] do
      conn = c.user |> TestFixtures.member_conn() |> get(path)

      html = html_response(conn, 200)
      assert html =~ ~s(<script type="module" src="/console/assets/index-abc.js">)
      assert [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"><\/head>/, html)
      assert token != ""
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "answers 503 with guidance when the console has not been built", c do
    File.rm!(c.index_path)

    conn = c.user |> TestFixtures.member_conn() |> get("/console")

    assert response(conn, 503) =~ "has not been built"
  end

  test "dev-server mode makes root-relative console URLs absolute to the dev server" do
    html =
      ~s(<script type="module" src="/console/@vite/client"></script><link href="/console/src/x.css">) <>
        ~s(<a href="/elsewhere">)

    assert Shell.absolutize_dev_urls(html, "http://127.0.0.1:5180/") ==
             ~s(<script type="module" src="http://127.0.0.1:5180/console/@vite/client"></script>) <>
               ~s(<link href="http://127.0.0.1:5180/console/src/x.css"><a href="/elsewhere">)
  end

  test "injects the token even when the document has no head" do
    assert Shell.inject_csrf("<p>x</p>", "a&b") ==
             ~s(<meta name="csrf-token" content="a&amp;b"><p>x</p>)
  end
end
