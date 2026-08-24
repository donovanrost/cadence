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
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModels
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  setup do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)

    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)
    :ok
  end

  test "an organization administrator approves and applies a persisted request" do
    %{admin: admin, organization: organization, mission: mission, request: request} =
      activation_request_fixture()

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(admin),
        ~p"/missions/#{mission.mission_id}/ops/activations"
      )

    assert has_element?(view, "#activation-requests-component.contents")
    assert has_element?(view, "#ops-context-rail-component")
    refute has_element?(view, "#activation-approval-inbox")

    initial_vue = activation_requests_vue(view)
    request_row = request_row(request, "Activation Requester")

    assert initial_vue.component == "OpsActivationRequests"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "decide" => JS.push("decide"),
             "review" => JS.push("review")
           }

    assert initial_vue.props == %{
             "page" => page_props(),
             "selected" => nil,
             "form" => decision_form_props("")
           }

    assert activation_request_rows(initial_vue) == [request_row]
    assert_json_safe(initial_vue)

    review_selector = "#review-activation-#{request.activation_request_id}"
    assert request_row["review"]["id"] == String.trim_leading(review_selector, "#")

    render_hook(view, "review", %{"request-id" => request.activation_request_id})

    reviewed_vue = activation_requests_vue(view)

    assert reviewed_vue.props == %{
             "page" => page_props(),
             "selected" => %{
               "activation_request_id" => request.activation_request_id,
               "binding_set_id" => "approval-inbox-basis",
               "binding_set_version" => 1
             },
             "form" => decision_form_props(request.activation_request_id)
           }

    assert reviewed_vue.props["form"]["id"] == "activation-decision-form"
    assert activation_request_stream_mutations(reviewed_vue) == []
    assert_json_safe(reviewed_vue)

    render_hook(view, "decide", %{
      "activation_decision" => %{
        "request_id" => request.activation_request_id,
        "reason" => "Not accepted by the component"
      },
      "decision" => "invalid"
    })

    assert has_element?(
             view,
             "#flash-error",
             "Could not record decision: invalid_decision"
           )

    error_vue = activation_requests_vue(view)
    assert error_vue.props == reviewed_vue.props
    assert activation_request_stream_mutations(error_vue) == []

    render_hook(view, "decide", %{
      "activation_decision" => %{
        "request_id" => request.activation_request_id,
        "reason" => "Approved by flight operations"
      },
      "decision" => "approved"
    })

    assert has_element?(view, "#flash-info", "Activation approved and applied.")

    approved_vue = activation_requests_vue(view)

    assert approved_vue.props == %{
             "page" => page_props(),
             "selected" => nil,
             "form" => decision_form_props("")
           }

    assert activation_request_stream_mutations(approved_vue) == [
             ["replace", "/activation_requests", []]
           ]

    assert_json_safe(approved_vue)

    assert {:ok, %{generation: 1}} =
             ControlActivations.fetch_active_basis(
               organization.organization_id,
               mission.mission_id
             )

    assert :ok = Cadence.Runtime.stop_mission(mission.mission_id)
  end

  test "an organization administrator rejects a persisted request" do
    %{
      admin: admin,
      mission: mission,
      request: request,
      requester_scope: requester_scope
    } = activation_request_fixture(requester_display_name: nil)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(admin),
        ~p"/missions/#{mission.mission_id}/ops/activations"
      )

    initial_vue = activation_requests_vue(view)
    request_row = request_row(request, request.requester_actor_id)

    assert activation_request_rows(initial_vue) == [request_row]
    assert request_row["requester_display"] == request.requester_actor_id

    render_hook(view, "review", %{"request-id" => request.activation_request_id})

    render_hook(view, "decide", %{
      "activation_decision" => %{
        "request_id" => request.activation_request_id,
        "reason" => "Rejected by flight operations"
      },
      "decision" => "rejected"
    })

    assert has_element?(view, "#flash-info", "Activation rejected.")

    assert {:ok, rejected} =
             ManagementActivations.fetch(requester_scope, request.activation_request_id)

    assert rejected.state == :rejected

    rejected_vue = activation_requests_vue(view)
    assert rejected_vue.props["selected"] == nil
    assert rejected_vue.props["form"] == decision_form_props("")

    assert activation_request_stream_mutations(rejected_vue) == [
             ["replace", "/activation_requests", []]
           ]

    assert_json_safe(rejected_vue)
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

  defp activation_request_fixture(opts \\ []) do
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

    layer =
      Layer.new(%{
        organization_id: organization.organization_id,
        mission_id: mission.mission_id,
        name: "Activation approval model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    assert {:ok, compilation} = MissionModels.compile_layers([layer])

    assert {:ok, revision} =
             MissionModels.approve_revision(
               organization.organization_id,
               mission.mission_id,
               compilation.revision.revision_id,
               %{"kind" => "test_fixture", "id" => "ops-activation-requests-live"}
             )

    requester =
      User.new(%{
        user_id: "activation-requester",
        email: "activation-requester@example.test",
        display_name: Keyword.get(opts, :requester_display_name, "Activation Requester"),
        capabilities: [:platform_admin]
      })

    requester_scope =
      Scope.new(%{
        user: requester,
        organization_id: organization.organization_id,
        admin_mode?: true
      })

    assert {:ok, request} =
             MissionModels.request_promotion(
               requester_scope,
               mission.mission_id,
               revision.revision_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    %{
      admin: admin,
      organization: organization,
      mission: mission,
      request: request,
      requester_scope: requester_scope
    }
  end

  defp page_props do
    %{
      "id" => "activation-approval-inbox",
      "heading" => "Activation approvals",
      "subtitle" => "Review governed mission changes before Control applies them to runtime.",
      "list" => %{
        "card_id" => "activation-approval-list",
        "id" => "activation-requests",
        "empty" => %{
          "id" => "activation-requests-empty",
          "copy" => "No activation requests are waiting for approval."
        }
      }
    }
  end

  defp decision_form_props(request_id) do
    %{
      "panel_id" => "activation-decision-panel",
      "id" => "activation-decision-form",
      "request_id" => %{
        "id" => "activation_decision_request_id",
        "name" => "activation_decision[request_id]",
        "type" => "hidden",
        "value" => request_id
      },
      "reason" => %{
        "id" => "activation_decision_reason",
        "name" => "activation_decision[reason]",
        "type" => "textarea",
        "label" => "Decision rationale",
        "required" => true,
        "value" => ""
      },
      "actions" => %{
        "reject" => %{
          "id" => "reject-activation-request",
          "name" => "decision",
          "value" => "rejected",
          "label" => "Reject"
        },
        "approve" => %{
          "id" => "approve-activation-request",
          "name" => "decision",
          "value" => "approved",
          "label" => "Approve and apply"
        }
      }
    }
  end

  defp request_row(request, requester_display) do
    %{
      "__dom_id" => "activation-request-#{request.activation_request_id}",
      "activation_request_id" => request.activation_request_id,
      "binding_set_id" => "approval-inbox-basis",
      "binding_set_version" => 1,
      "status" => %{"label" => "Pending approval"},
      "requester_display" => requester_display,
      "review" => %{
        "id" => "review-activation-#{request.activation_request_id}",
        "label" => "Review"
      }
    }
  end

  defp activation_requests_vue(view) do
    LiveVue.Test.get_vue(view, id: "activation-requests-component")
  end

  defp activation_request_rows(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/activation_requests/" <> _index, _request] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, request] -> request end)
  end

  defp activation_request_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end
end
