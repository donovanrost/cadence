Code.require_file(Path.expand("../../support/federation_browser_smoke_setup.exs", __DIR__))

defmodule CadenceWeb.Assets.ConsoleFederationSmokeTest do
  @moduledoc """
  The federation contract on the console (it gates §11c(C)): the test-only surface_fixture
  application's surfaces and a telemetry_decom canary, mounted by the console's app routes from
  signed, activated releases. Driver for frontend/tools/phoenix/console_federation_smoke.mjs.
  """
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  alias Cadence.Applications.FixtureContributors
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner, as: Runner
  alias CadenceWeb.Assets.{FederationBrowserSmokeSetup, FederationReleaseFixture}
  alias CadenceWeb.TestFixtures

  setup do
    # The fixture application exists only while this test runs (never in test_helper.exs).
    :ok = FixtureContributors.enable()
    on_exit(&FixtureContributors.disable/0)

    previous = Application.get_env(:cadence_web, :frontend_release_publication, :not_configured)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      FederationReleaseFixture.publication_config()
    )

    on_exit(fn ->
      case previous do
        :not_configured -> Application.delete_env(:cadence_web, :frontend_release_publication)
        config -> Application.put_env(:cadence_web, :frontend_release_publication, config)
      end
    end)

    :ok
  end

  @tag :browser_smoke
  test "the console mounts federated surfaces under the federation contract", %{
    sandbox_owner: owner
  } do
    app_root = Path.expand("../../..", __DIR__)
    context = FederationBrowserSmokeSetup.persist_context!()
    port = Runner.start_browser_endpoint_on_ephemeral_port!(owner)

    release =
      FederationReleaseFixture.prepare_and_activate!(app_root,
        sandbox_owner: owner,
        surface_fixture: true
      )

    on_exit(fn -> FederationReleaseFixture.cleanup!(release) end)

    args = [
      Path.expand("../../../../../frontend/tools/phoenix/console_federation_smoke.mjs", __DIR__),
      "--base-url",
      "http://127.0.0.1:#{port}",
      "--login-email",
      context.user.email,
      "--org-slug",
      context.scope.organization.slug,
      "--mission-slug",
      context.mission.slug,
      "--mission-id",
      context.mission.mission_id,
      "--spacecraft-id",
      context.spacecraft.spacecraft_id,
      "--fixture-n-minus-1-release-id",
      Map.fetch!(release.release_ids.n_minus_1, "surface_fixture"),
      "--fixture-n-release-id",
      Map.fetch!(release.release_ids.n, "surface_fixture"),
      "--federation-lifecycle-url",
      release.lifecycle.url
    ]

    {output, status} =
      Runner.run_dashboard_viewport_smoke(args,
        cd: app_root,
        timeout: 300_000,
        shutdown_timeout: 15_000,
        stdin: Jason.encode!(%{"password" => TestFixtures.default_password()}) <> "\n"
      )

    assert status == 0, output
    assert output =~ "CONSOLE_FEDERATION_SMOKE_OK"
  end
end
