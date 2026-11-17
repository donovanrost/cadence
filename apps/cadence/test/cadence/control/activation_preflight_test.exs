defmodule Cadence.Control.ActivationPreflightTest do
  @moduledoc """
  An approval is recorded only for a request whose apply could run (director 11-17): every approve
  path runs the deterministic checks an apply runs (`Control.Activations.deterministic_check_list/0`)
  BEFORE deciding. A refused request records no decision and stays pending, and the refusal is the
  code execute would have hit after recording 'approved'.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.ActivationRequests
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Missions
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Management.Activations.{ActivationDecisionRow, ActivationRequestRow}
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModelCatalogNaming
  alias Cadence.MissionModels
  alias Cadence.MissionModels.RevisionRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime

  @organization_id "org-activation-preflight"

  setup do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)
    mission_id = "mission-preflight-#{System.unique_integer([:positive])}"
    persist_mission_scope(@organization_id, mission_id)

    on_exit(fn ->
      Application.put_env(:cadence, :activation_governance, previous)
      Missions.stop(mission_id)
      Runtime.stop_mission(mission_id)
    end)

    binding_set = persist_binding_set(mission_id)
    revision = compile_and_approve(mission_id)

    {:ok, request} =
      MissionModels.request_promotion(
        user_scope("requester"),
        mission_id,
        revision.revision_id,
        binding_set.binding_set_id,
        binding_set.version
      )

    assert request.state == :approval_pending

    %{
      mission_id: mission_id,
      request: request,
      revision: revision,
      approver: user_scope("approver")
    }
  end

  test "a request whose approved content changed isn't approved; nothing is recorded", c do
    set_request(c.request, binding_set_content_sha256: "not-the-binding-set")

    assert {:error, :approved_activation_content_mismatch} = approve(c)
    assert_undecided(c)
  end

  test "a request whose model was un-approved since isn't approved", c do
    {1, _} =
      RevisionRow
      |> where([row], row.revision_id == ^c.revision.revision_id)
      |> Repo.update_all(set: [status: "candidate"])

    assert {:error, :mission_model_revision_not_approved} = approve(c)
    assert_undecided(c)
  end

  test "a request made under another policy isn't approved", c do
    set_request(c.request, policy_document: JsonDocument.wrap_value(%{"policy" => "an-old-one"}))

    assert {:error, :activation_policy_changed} = approve(c)
    assert_undecided(c)
  end

  test "an applicable request is approved as before", c do
    assert {:ok, _request, _decision, _approved} = approve(c)
    assert [_one] = decisions(c)
  end

  test "approve runs the SAME check list as execute: a new check refuses on every approve path",
       c do
    probe = fn _activation, _binding_set -> {:error, :drift_probe} end
    checks = ControlActivations.deterministic_check_list() ++ [probe]

    assert {:error, :drift_probe} =
             ControlActivations.approve(c.approver, c.request.activation_request_id, "ok",
               checks: checks
             )

    assert {:error, :drift_probe} =
             ActivationRequests.approve(
               c.approver,
               c.mission_id,
               c.request.activation_request_id,
               %{"reason" => "ok"},
               checks: checks
             )

    assert_undecided(c)
  end

  defp approve(c),
    do: ControlActivations.approve(c.approver, c.request.activation_request_id, "Reviewed")

  defp assert_undecided(c) do
    assert decisions(c) == []

    assert {:ok, %{state: :approval_pending}} =
             ManagementActivations.fetch(c.approver, c.request.activation_request_id)
  end

  defp decisions(c) do
    ActivationDecisionRow
    |> where([row], row.activation_request_id == ^c.request.activation_request_id)
    |> Repo.all()
  end

  defp set_request(request, fields) do
    {1, _} =
      ActivationRequestRow
      |> where([row], row.activation_request_id == ^request.activation_request_id)
      |> Repo.update_all(set: fields)
  end

  defp user_scope(prefix) do
    user_id = "#{prefix}-#{System.unique_integer([:positive])}"

    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id,
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: @organization_id, admin_mode?: true})
  end

  defp persist_binding_set(mission_id) do
    {:ok, persisted} =
      Cadence.Governance.persist_binding_set(
        BindingSet.new(%{
          organization_id: @organization_id,
          mission_id: mission_id,
          binding_set_id: "preflight-binding",
          version: 1
        })
      )

    persisted
  end

  defp compile_and_approve(mission_id) do
    layer =
      Layer.new(%{
        organization_id: @organization_id,
        mission_id: mission_id,
        name: "preflight model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compilation} = MissionModels.compile_layers([layer])

    MissionModelCatalogNaming.name!(
      @organization_id,
      mission_id,
      compilation.revision.revision_id
    )

    {:ok, revision} =
      MissionModelApproval.approve!(
        @organization_id,
        mission_id,
        compilation.revision.revision_id
      )

    revision
  end
end
