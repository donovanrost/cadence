defmodule CadenceWeb.Console.ActivationRequestAPITest do
  @moduledoc "§11 L10: console activation approvals (list, show, approve, reject, resume)."
  use CadenceWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.ActivationRequests
  alias Cadence.Management.Activations
  alias CadenceWeb.TestFixtures

  setup do
    approver = TestFixtures.persist_user!(display_name: "Ada Approver")
    requester = TestFixtures.persist_user!(display_name: "Flight requester")
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    TestFixtures.grant_membership!(requester, org)
    mission = TestFixtures.persist_mission!(org)

    scope = %Scope{
      actor_kind: :user,
      user: requester,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }

    %{
      approver: approver,
      requester: requester,
      org: org,
      mission: mission,
      scope: scope,
      base: "/api/console/v1/missions/#{mission.mission_id}/activations"
    }
  end

  test "pending rows: who may decide, what it activates, and the detail's facts", c do
    request = request(c)

    data = c.approver |> get_conn(c.base) |> json_response(200) |> Map.fetch!("data")
    assert data["permissions"] == ["activations.approve"]
    assert data["next"] == nil

    assert [row] = data["requests"]
    assert row["id"] == request.activation_request_id
    assert row["state"] == "approval_pending"
    assert row["can_decide"] == true
    assert row["decision"] == nil
    assert row["execution"] == nil
    assert %{"name" => "Flight requester", "kind" => "user"} = row["requested_by"]
    assert %{"version" => 1} = row["binding_set"]
    assert row["summary"] == "Mission activation"

    # The requester sees it but may not decide it.
    [mine] = c.requester |> get_conn(c.base) |> json_response(200) |> get_in(["data", "requests"])
    assert mine["can_decide"] == false

    detail =
      c.approver
      |> get_conn(c.base <> "/" <> row["id"])
      |> json_response(200)
      |> Map.fetch!("data")

    assert detail["permissions"] == ["activations.approve"]
    assert Enum.any?(detail["details"], &(&1["label"] == "Binding set"))
    assert detail["comparison"] == nil

    assert [] =
             c.approver
             |> get_conn(c.base <> "?state=decided")
             |> json_response(200)
             |> get_in(["data", "requests"])
  end

  test "reject records the decision; a second decision is 409 not_pending", c do
    id = request(c).activation_request_id

    assert %{"code" => "invalid_params", "details" => %{"reason" => "Say why."}} =
             c.approver
             |> post_conn(c.base <> "/#{id}/reject", %{"reason" => " "})
             |> json_response(422)
             |> Map.fetch!("error")

    data =
      c.approver
      |> post_conn(c.base <> "/#{id}/reject", %{"reason" => "Not this basis"})
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"state" => "rejected", "decision" => decision} = data["request"]

    assert %{
             "state" => "rejected",
             "reason" => "Not this basis",
             "by" => %{"name" => "Ada Approver"}
           } = decision

    refute Map.has_key?(data, "outcome")

    assert %{"code" => "not_pending", "details" => %{"state" => "rejected"}} =
             c.approver
             |> post_conn(c.base <> "/#{id}/approve", %{"reason" => "Late"})
             |> json_response(409)
             |> Map.fetch!("error")

    assert %{"code" => "nothing_to_resume", "details" => %{"state" => "rejected"}} =
             c.approver
             |> post_conn(c.base <> "/#{id}/resume", %{})
             |> json_response(409)
             |> Map.fetch!("error")
  end

  test "the requester can't approve their own request: the kind-prefixed code, via_service null (#275)",
       c do
    id = request(c).activation_request_id

    # #275 (U94): requester only, no details.rule; #280's via_service always sent.
    assert %{
             "code" => "activation_self_approval_forbidden",
             "details" => %{"via_service" => nil} = details
           } =
             c.requester
             |> post_conn(c.base <> "/#{id}/approve", %{"reason" => "Mine"})
             |> json_response(403)
             |> Map.fetch!("error")

    refute Map.has_key?(details, "rule")
  end

  test "approve answers with the row and whether it applied", c do
    # An applicable request (an approved model): approve refuses one whose apply couldn't run
    # (Control.Activations.preflight/2, director 11-17).
    id = applicable_request(c).activation_request_id

    data =
      c.approver
      |> post_conn(c.base <> "/#{id}/approve", %{"reason" => "Reviewed exact basis"})
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["outcome"] in ["applied", "needs_review"]

    assert %{"state" => "approved", "decision" => %{"state" => "approved"}, "can_decide" => false} =
             data["request"]

    assert %{"state" => state, "retryable" => retryable, "finished_at" => finished} =
             data["request"]["execution"]

    assert state in ["succeeded", "failed"]
    assert is_boolean(retryable)
    # When the apply finished (ux #227: 'Applied … on T'), not when it was decided.
    assert {:ok, _, 0} = DateTime.from_iso8601(finished)
  end

  test "the requester withdraws; nobody else can; a newer request supersedes an older one", c do
    id = request(c).activation_request_id

    assert %{"code" => "not_requester"} =
             c.approver
             |> post_conn(c.base <> "/#{id}/withdraw", %{"reason" => "Not mine"})
             |> json_response(403)
             |> Map.fetch!("error")

    data =
      c.requester
      |> post_conn(c.base <> "/#{id}/withdraw", %{"reason" => "Wrong basis"})
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"state" => "withdrawn", "decision" => %{"state" => "withdrawn"}} = data["request"]

    older = request(c)
    newer = request(c, older.binding_set_id)

    decided =
      c.approver
      |> get_conn(c.base <> "?state=decided")
      |> json_response(200)
      |> get_in(["data", "requests"])

    assert %{"state" => "superseded", "superseded_by" => superseded_by} =
             Enum.find(decided, &(&1["id"] == older.activation_request_id))

    assert superseded_by == newer.activation_request_id
    assert Enum.any?(decided, &(&1["id"] == id and &1["state"] == "withdrawn"))
  end

  test "another mission's request is not found here", c do
    id = request(c).activation_request_id
    other = TestFixtures.persist_mission!(c.org)
    path = "/api/console/v1/missions/#{other.mission_id}/activations/#{id}"

    assert c.approver |> get_conn(path) |> json_response(404) |> get_in(["error", "code"]) ==
             "activation_request_not_found"

    assert c.approver
           |> post_conn(path <> "/approve", %{"reason" => "x"})
           |> json_response(404)
           |> get_in(["error", "code"]) ==
             "activation_request_not_found"
  end

  test "an unknown tab or cursor is a 422", c do
    assert c.approver |> get_conn(c.base <> "?state=everything") |> json_response(422)
    assert c.approver |> get_conn(c.base <> "?before=nope") |> json_response(422)
  end

  defp get_conn(user, path), do: user |> TestFixtures.member_conn() |> get(path)
  defp post_conn(user, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  # #263 (ca-security, api-ops): an apply that exits after the approval commits (a pool or
  # GenServer timeout) reads needs_review, never a 500 for a recorded approval; the cause is logged.
  test "an apply that exits after the approval is recorded reads needs_review", c do
    id = applicable_request(c).activation_request_id
    approver = %{c.scope | user: c.approver}

    log =
      capture_log(fn ->
        assert {:ok, %{outcome: "needs_review"}} =
                 ActivationRequests.approve(
                   approver,
                   c.mission.mission_id,
                   id,
                   %{"reason" => "Reviewed exact basis"},
                   execute: fn _approved ->
                     exit({:timeout, {GenServer, :call, [:pool, %{token: "secret-arg"}, 5_000]}})
                   end
                 )
      end)

    assert log =~
             "activation request #{id}: approved, but its apply didn't finish: " <>
               "exit: :timeout in GenServer.call"

    refute log =~ "secret-arg"
    assert {:ok, %{state: :approved}} = Activations.fetch(approver, id)
  end

  defp applicable_request(c) do
    binding =
      BindingSet.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        binding_set_id: Cadence.Ids.new("review-basis"),
        version: 1
      })

    {:ok, binding} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding)

    layer =
      Layer.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        name: "applicable model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compilation} = Cadence.MissionModels.compile_layers([layer])

    # The orphan guard (item 3): an approved model revision is one a catalog revision names.
    Cadence.MissionModelCatalogNaming.name!(
      c.org.organization_id,
      c.mission.mission_id,
      compilation.revision.revision_id
    )

    {:ok, _approved} =
      Cadence.MissionModelApproval.approve!(
        c.org.organization_id,
        c.mission.mission_id,
        compilation.revision.revision_id
      )

    {:ok, request} =
      Cadence.MissionModels.request_promotion(
        c.scope,
        c.mission.mission_id,
        compilation.revision.revision_id,
        binding.binding_set_id,
        binding.version
      )

    request
  end

  defp request(c, binding_set_id \\ nil) do
    id =
      binding_set_id ||
        (
          binding =
            BindingSet.new(%{
              organization_id: c.org.organization_id,
              mission_id: c.mission.mission_id,
              binding_set_id: Cadence.Ids.new("review-basis"),
              version: 1
            })

          {:ok, binding} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding)
          binding.binding_set_id
        )

    {:ok, request} = Activations.request(c.scope, c.mission.mission_id, id, 1)
    request
  end
end
