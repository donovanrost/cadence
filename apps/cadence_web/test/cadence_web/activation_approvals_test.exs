defmodule CadenceWeb.ActivationApprovalsTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.Reads.ActivationApprovals
  alias Cadence.Runtime.Missions, as: RuntimeMissions
  alias CadenceWeb.TestFixtures

  @validator Path.expand(
               "../../../../frontend/apps/host/src/capability-management/features/activation-approvals/validation.ts",
               __DIR__
             )

  setup do
    user = TestFixtures.persist_user!()
    requester = TestFixtures.persist_user!(display_name: "Flight requester")
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    TestFixtures.grant_membership!(requester, org)
    mission = TestFixtures.persist_mission!(org)

    scope = %Scope{
      actor_kind: :user,
      user: user,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }

    {:ok,
     user: user,
     requester: requester,
     org: org,
     mission: mission,
     scope: scope,
     conn: TestFixtures.member_conn(user),
     path: "/missions/#{mission.mission_id}/ops/activations"}
  end

  test "real pending requests satisfy the feature contract without an Ops installation",
       context do
    pending = request(context)
    {:ok, view, _} = live(context.conn, context.path)

    assert %{"version" => 1, "status" => "ready", "data" => data, "token" => token} =
             snapshot(view)

    assert is_binary(token)

    assert [%{"activation_request_id" => id, "requester_display" => "Flight requester"}] =
             data["activation_requests"]

    assert id == pending.activation_request_id

    script = """
    import {admitInbox} from #{Jason.encode!(@validator)};
    const snapshot = JSON.parse(process.argv[1]);
    if (!admitInbox(snapshot, snapshot.context)) throw new Error("Invalid producer inbox");
    """

    {output, code} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(snapshot(view))],
        stderr_to_stdout: true
      )

    assert code == 0, output
  end

  test "rejection is durable, rotates the token, and cannot be replayed", context do
    pending = request(context)
    {:ok, view, _} = live(context.conn, context.path)
    token = snapshot(view)["token"]
    act(view, context.path, token, pending, "rejected")

    assert {:ok, %{state: :rejected}} =
             Activations.fetch(context.scope, pending.activation_request_id)

    assert snapshot(view)["data"]["activation_requests"] == []
    refute snapshot(view)["token"] == token
    act(view, context.path, token, pending, "approved")

    assert {:ok, %{state: :rejected}} =
             Activations.fetch(context.scope, pending.activation_request_id)
  end

  test "self-review, malformed decisions, and cross-mission requests cannot mutate intent",
       context do
    own = request(context, requester: context.user)

    assert {:error, :activation_self_approval_forbidden} =
             ControlActivations.review(
               context.scope,
               context.mission.mission_id,
               input(own, "approved")
             )

    pending = request(context)
    other = TestFixtures.persist_mission!(context.org)

    for payload <- [
          Map.put(input(pending, "approved"), "mission_id", other.mission_id),
          put_in(input(pending, "approved"), ["activation_decision", "reason"], " "),
          put_in(
            input(pending, "approved"),
            ["activation_decision", "reason"],
            String.duplicate("x", 4097)
          ),
          put_in(input(pending, "approved"), ["activation_decision", "reason"], %{}),
          input(pending, "unexpected")
        ] do
      assert {:error, _} =
               ControlActivations.review(context.scope, context.mission.mission_id, payload)
    end

    assert {:error, _} =
             ControlActivations.review(
               %{context.scope | mission_id: nil},
               other.mission_id,
               input(pending, "rejected")
             )

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(context.scope, pending.activation_request_id)
  end

  test "ordinary members can read the inbox and other organizations cannot", context do
    request(context)

    assert {:ok, _} =
             ActivationApprovals.load(
               %{context.scope | capabilities: MapSet.new()},
               context.mission.mission_id
             )

    assert {:error, _} =
             ActivationApprovals.load(
               %{context.scope | organization_id: "another-org"},
               context.mission.mission_id
             )
  end

  test "navigation invalidates old page tokens and revoked sessions cannot decide", context do
    pending = request(context)
    {:ok, view, _} = live(context.conn, context.path)
    token = snapshot(view)["token"]
    render_hook(view, "host:context", %{"path" => "/missions/#{context.mission.mission_id}"})
    render_hook(view, "host:context", %{"path" => context.path})
    refute snapshot(view)["token"] == token
    act(view, context.path, token, pending, "rejected")

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(context.scope, pending.activation_request_id)

    token = snapshot(view)["token"]
    :ok = Cadence.Auth.revoke_user_session(get_session(context.conn, :user_session_token))
    act(view, context.path, token, pending, "rejected")
    assert_redirect(view, "/sign-in")

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(context.scope, pending.activation_request_id)
  end

  test "approved intent is reported separately when runtime application fails", context do
    pending = request(context)

    assert {:ok, %{"decision" => "approved", "outcome" => "application_needs_review"}} =
             ControlActivations.review(
               context.scope,
               context.mission.mission_id,
               input(pending, "approved")
             )

    assert {:ok, %{state: :approved}} =
             Activations.fetch(context.scope, pending.activation_request_id)

    assert {:error, :activation_request_not_pending_approval} =
             ControlActivations.review(
               context.scope,
               context.mission.mission_id,
               input(pending, "approved")
             )
  end

  @tag :runtime
  test "the host decision executes the approved exact model and records its runtime generation",
       context do
    pending = request(context, model: true)
    {:ok, view, _} = live(context.conn, context.path)
    act(view, context.path, snapshot(view)["token"], pending, "approved")

    assert {:ok, %{state: :approved}} =
             Activations.fetch(context.scope, pending.activation_request_id)

    assert {:ok, %{status: :succeeded, activation_request_id: id}} =
             ControlActivations.fetch_execution(pending.activation_request_id)

    assert id == pending.activation_request_id

    assert {:ok, %{activation_request_id: ^id, generation: 1}} =
             RuntimeMissions.applied_spec(context.mission.mission_id)

    assert snapshot(view)["data"]["activation_requests"] == []
  end

  defp request(context, opts \\ []) do
    binding =
      BindingSet.new(%{
        organization_id: context.org.organization_id,
        mission_id: context.mission.mission_id,
        binding_set_id: Cadence.Ids.new("review-basis"),
        version: 1
      })

    assert {:ok, binding} =
             Cadence.Governance.persist_binding_set(context.org.organization_id, binding)

    scope = %{context.scope | user: Keyword.get(opts, :requester, context.requester)}

    result =
      if Keyword.get(opts, :model, false) do
        layer =
          Layer.new(%{
            organization_id: context.org.organization_id,
            mission_id: context.mission.mission_id,
            name: "Review model",
            declarations: [%{kind: :space_system, qualified_name: "/"}]
          })

        {:ok, compilation} = MissionModels.compile_layers([layer])

        {:ok, revision} =
          MissionModels.approve_revision(
            context.org.organization_id,
            context.mission.mission_id,
            compilation.revision.revision_id,
            %{"kind" => "test_fixture", "id" => "review"}
          )

        MissionModels.request_promotion(
          scope,
          context.mission.mission_id,
          revision.revision_id,
          binding.binding_set_id,
          1
        )
      else
        Activations.request(scope, context.mission.mission_id, binding.binding_set_id, 1)
      end

    assert {:ok, request} = result
    request
  end

  defp input(request, decision),
    do: %{
      "activation_decision" => %{
        "request_id" => request.activation_request_id,
        "reason" => "Reviewed exact basis"
      },
      "decision" => decision
    }

  defp snapshot(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "activation_approvals"
      ]

  defp act(view, path, token, request, decision),
    do:
      render_hook(view, "host:activation", %{
        "path" => path,
        "token" => token,
        "input" => input(request, decision)
      })
end
