defmodule Cadence.Control.Commanding.GroupServiceRequesterTest do
  @moduledoc """
  #708: a service identity may request a command group and never decide one.

  - The requester document comes from the credential's scope, nothing else.
  - A service's group always needs a person's GO, whatever its commands and reach say.
  - Separation of duties is `Accountability`'s: the service's issuer and rotators can't GO it
    (#622 never had a rotator test), and with nobody accountable nobody can.
  - A service is refused every decision before any group state is read.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Auth
  alias Cadence.Auth.{ServiceIdentity, ServiceIdentityKeys}
  alias Cadence.Control.Commanding.{GroupCreation, GroupDecision, GroupSubmission}
  alias Cadence.Reads.CommandPreflight
  alias Cadence.ServiceIdentityFixtures

  setup do
    c = setup!(1)
    commandable_pass!(c.org, c.mission, hd(c.spacecraft))

    issuer = operator!(c, "Issuer")
    rotator = operator!(c, "Rotator")
    approver = operator!(c, "Approver")

    {:ok, %{service_identity: service, api_token: token}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          display_name: "Pass scripts",
          capabilities: [:mission_admin]
        }),
        issuer
      )

    {:ok, scope} = Auth.authenticate_api_token(token)

    Map.merge(c, %{
      issuer: issuer,
      rotator: rotator,
      approver: approver,
      service: service,
      service_scope: scope
    })
  end

  # A routine command to one target: with a person requesting, nothing needs a second GO.
  defp routine(c, extra \\ %{}),
    do: draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})], extra)

  defp service_actor(c),
    do: %{"actor_kind" => "service", "service_identity_id" => c.service.service_identity_id}

  defp create(c, scope, draft, opts \\ []) do
    {:ok, pre} = CommandPreflight.run(c.org, c.mission, actor_for(c, scope), draft)
    GroupCreation.create(scope, c.mission, draft, [preflight_digest: pre.digest] ++ opts)
  end

  defp actor_for(c, %{actor_kind: :service}), do: service_actor(c)
  defp actor_for(c, _scope), do: actor(c)

  test "the requester document is the credential's own service identity", c do
    assert {:ok, org, actor} = GroupSubmission.requester(c.service_scope, c.mission)
    assert org == c.org
    assert actor == service_actor(c)
  end

  test "a service is held to its own mission", c do
    other = Cadence.CommandReviewFixtures.scope!()

    assert {:error, :forbidden} = GroupSubmission.requester(c.service_scope, other.mission)
    assert {:error, :forbidden} = GroupSubmission.requester(c.service_scope, "no-such-mission")
  end

  test "a service's preflight says a person must give the GO; a person's routine one does not",
       c do
    {:ok, pre} = CommandPreflight.run(c.org, c.mission, service_actor(c), routine(c))
    assert pre.policy.second_go_required
    assert Enum.any?(pre.policy.reasons, &(&1.key == :service_requester))

    {:ok, pre} = CommandPreflight.run(c.org, c.mission, actor(c), routine(c))
    refute pre.policy.second_go_required
  end

  test "the same routine command from a person is queued with no second GO (the control)", c do
    assert {:ok, queued} = create(c, c.scope, routine(c))
    assert queued.state == :queued
    refute queued.policy["second_go_required"]
  end

  test "a non-hazardous single-target service request waits for a person", c do
    assert {:ok, group} = create(c, c.service_scope, routine(c, %{log_entry: "Scripted pass."}))
    assert group.state == :approval_pending
    assert group.requested_by == service_actor(c)
    assert group.policy["second_go_required"] == true
    assert group.member_count == 1
  end

  test "a service's group needs the log entry its second GO is read against", c do
    assert {:error, :log_entry_required} = create(c, c.service_scope, routine(c))
  end

  test "an operation id replays as duplicate_operation", c do
    d = routine(c, %{log_entry: "Scripted pass."})
    assert {:ok, group} = create(c, c.service_scope, d, operation_id: "op-1")

    assert {:error, {:duplicate_operation, id}} =
             create(c, c.service_scope, d, operation_id: "op-1")

    assert id == group.command_group_id
  end

  test "the issuer and a rotator can't GO the group; another person can (#622)", c do
    {:ok, _rotated} =
      ServiceIdentityKeys.rotate(c.org, c.service.service_identity_id, c.rotator)

    {:ok, group} = create(c, c.service_scope, routine(c, %{log_entry: "Scripted pass."}))
    id = group.command_group_id

    for person <- [c.issuer, c.rotator] do
      assert {:error, {:command_group_self_approval_not_allowed, %{via_service: %{id: via}}}} =
               GroupDecision.decide(person, c.mission, id, %{kind: :go})

      assert via == c.service.service_identity_id
    end

    assert {:ok, %{state: :queued}} =
             GroupDecision.decide(c.approver, c.mission, id, %{kind: :go})
  end

  test "with nobody accountable for the service, nobody can GO its group", c do
    {:ok, group} = create(c, c.service_scope, routine(c, %{log_entry: "Scripted pass."}))
    ServiceIdentityFixtures.forget_accountables!(c.service.service_identity_id)

    assert {:error, {:command_group_approver_authors_unknown, %{service: _}}} =
             GroupDecision.decide(c.approver, c.mission, group.command_group_id, %{kind: :go})
  end

  test "a service is refused every decision before any group state is read", c do
    {:ok, group} = create(c, c.service_scope, routine(c, %{log_entry: "Scripted pass."}))

    for decision <- [%{kind: :go}, %{kind: :no_go, note: "no"}, %{kind: :bogus}] do
      assert {:error, :unavailable} =
               GroupDecision.decide(c.service_scope, c.mission, group.command_group_id, decision)

      assert {:error, :unavailable} =
               GroupDecision.decide(c.service_scope, c.mission, "no-such-group", decision)
    end

    assert {:ok, %{state: :approval_pending}} =
             Cadence.Commanding.Groups.GroupStore.fetch(c.org, c.mission, group.command_group_id)
  end
end
