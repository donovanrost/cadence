Code.require_file(Path.expand("../../support/federation_browser_smoke_setup.exs", __DIR__))

defmodule CadenceWeb.Assets.FederationBrowserSmokeTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  alias CadenceWeb.Assets.FederationBrowserSmokeSetup

  @tag :browser_smoke
  test "authenticated production federation surfaces pass the browser gate", %{
    sandbox_owner: sandbox_owner
  } do
    assert :ok = FederationBrowserSmokeSetup.run(sandbox_owner)
  end
end
