Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_runner.exs", __DIR__))

defmodule CadenceWeb.Assets.AdminModeBrowserSmokeTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.Assets.DashboardRenderedViewportRunner, as: Runner
  alias CadenceWeb.TestFixtures

  for activation <- ["pointer", "keyboard"] do
    @tag :browser_smoke
    @tag timeout: 120_000
    test "native session forms support #{activation} activation", %{sandbox_owner: owner} do
      user = TestFixtures.persist_user!(capabilities: [:platform_admin])
      organization = TestFixtures.persist_org!()
      TestFixtures.grant_membership!(user, organization)
      other_organization = TestFixtures.persist_org!()
      TestFixtures.grant_membership!(user, other_organization)
      port = Runner.start_browser_endpoint_on_ephemeral_port!(owner)

      script =
        Path.expand("../../../../../frontend/tools/phoenix/admin_mode_browser_smoke.mjs", __DIR__)

      result =
        Runner.run_dashboard_viewport_smoke(
          [script, "http://127.0.0.1:#{port}", user.email, unquote(activation)],
          stdin: Jason.encode!(%{password: TestFixtures.default_password()}) <> "\n",
          timeout: 90_000
        )

      assert {output, 0} = result
      assert output =~ "Admin mode browser smoke passed"
    end
  end
end
