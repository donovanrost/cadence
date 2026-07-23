defmodule CadenceWeb.OpsActivationRequestsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations
  alias CadenceWeb.TestFixtures

  setup do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)

    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)
    :ok
  end

  test "an organization administrator approves and applies a persisted request" do
    admin = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(admin, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)

    binding_set =
      BindingSet.new(%{
        organization_id: organization.organization_id,
        mission_id: mission.mission_id,
        binding_set_id: "approval-inbox-basis",
        version: 1
      })

    assert {:ok, ^binding_set} =
             Cadence.Governance.persist_binding_set(organization.organization_id, binding_set)

    requester =
      User.new(%{
        user_id: "activation-requester",
        email: "activation-requester@example.test",
        display_name: "Activation Requester",
        capabilities: [:platform_admin]
      })

    assert {:ok, request} =
             Activations.request(
               Scope.new(%{user: requester, organization_id: organization.organization_id}),
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(admin),
        ~p"/missions/#{mission.mission_id}/ops/activations"
      )

    assert has_element?(view, "#activation-approval-inbox")

    review_selector = "#review-activation-#{request.activation_request_id}"
    assert has_element?(view, review_selector)
    view |> element(review_selector) |> render_click()

    assert has_element?(view, "#activation-decision-form")

    view
    |> form("#activation-decision-form",
      activation_decision: %{
        request_id: request.activation_request_id,
        reason: "Approved by flight operations"
      }
    )
    |> render_submit(%{"decision" => "approved"})

    refute has_element?(view, review_selector)

    assert {:ok, %{generation: 1}} =
             Cadence.Control.Activations.fetch_active_basis(
               organization.organization_id,
               mission.mission_id
             )

    assert :ok = Cadence.Runtime.stop_mission(mission.mission_id)
  end

  test "the approval inbox is router-protected from ordinary members" do
    member = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(member, organization)
    mission = TestFixtures.persist_mission!(organization)

    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               TestFixtures.member_conn(member),
               ~p"/missions/#{mission.mission_id}/ops/activations"
             )
  end
end
