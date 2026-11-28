Code.require_file(Path.join(__DIR__, "dashboard_rendered_viewport_runner.exs"))
Code.require_file(Path.join(__DIR__, "federation_release_fixture.exs"))

defmodule CadenceWeb.Assets.FederationBrowserSmokeSetup do
  @moduledoc false

  alias Cadence.Auth.Scope
  alias CadenceWeb.TestFixtures

  def persist_context! do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Federation Browser Organization")
    membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "federation-browser",
        display_name: "Federation Browser Mission"
      )

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    %{user: user, scope: scope, mission: mission}
  end
end
