defmodule Cadence.ContactPlanning.AutomationGrantReviewTest do
  @moduledoc """
  #283 (ux U105): under 'independent' an automation grant is proposed and authorizes nothing
  until a second org admin approves it; under 'direct' it's active at once. Revoke and narrow are
  one-person tightenings. Every act is person-only and writes one append-only decision.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Auth.Scope
  alias Cadence.AutomationGrantFixtures, as: F

  alias Cadence.ContactPlanning.{
    AutomationGrant,
    AutomationGrantDecisions,
    AutomationGrantReview,
    AutomationGrants
  }

  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Contacts.Store.AutomationGrantRow

  setup do
    F.setup!("grant-review")
  end

  defp propose!(c, overrides \\ %{}, now \\ F.now()) do
    assert {:ok, grant} =
             AutomationGrants.issue(c.proposer, c.mission, F.grant_attrs(c.service, overrides),
               now: now
             )

    grant
  end

  defp approve(c, scope, grant, now \\ F.now()),
    do:
      AutomationGrants.approve(scope, c.mission, grant.automation_grant_id, grant.content_sha256,
        now: now
      )

  defp active!(c, overrides \\ %{}) do
    assert {:ok, grant} = approve(c, c.approver, propose!(c, overrides))
    grant
  end

  defp use_grant(c, grant, now \\ F.now()),
    do:
      AutomationGrants.authorize(
        c.service_scope,
        c.mission,
        grant.automation_grant_id,
        :plan,
        %{horizon_seconds: 3_600},
        now: now
      )

  defp narrow(c, grant, changes),
    do:
      AutomationGrants.narrow(c.third, c.mission, grant.automation_grant_id, changes,
        now: F.now()
      )

  defp decisions(c, grant),
    do:
      c.org
      |> AutomationGrantDecisions.list(c.mission, grant.automation_grant_id)
      |> Enum.map(& &1.decision)

  describe "proposing" do
    test "under independent a grant is proposed and authorizes nothing", c do
      grant = propose!(c)

      assert %{lifecycle_state: :proposed, valid_from: nil, valid_until: nil} = grant
      assert grant.validity_seconds == 86_400
      assert grant.proposal_expires_at == DateTime.add(F.now(), 72 * 3600, :second)

      assert {:error, {:automation_grant_not_active, %{state: :proposed}}} = use_grant(c, grant)
      assert decisions(c, grant) == [:proposed]
    end

    test "under direct the proposer's grant is active at once, and no new refusal", c do
      direct!(c)
      grant = propose!(c)

      assert %{lifecycle_state: :active, approved_by: approved_by} = grant
      assert approved_by == c.proposer.user.user_id
      assert grant.valid_from == F.now()
      assert {:ok, _grant} = use_grant(c, grant)
      assert decisions(c, grant) == [:not_required]
    end

    test "only an org admin, and only a person, proposes", c do
      assert {:error, :forbidden} =
               AutomationGrants.issue(c.member, c.mission, F.grant_attrs(c.service))

      assert {:error, :authenticated_user_required} =
               AutomationGrants.issue(admin_service(c), c.mission, F.grant_attrs(c.service))
    end
  end

  describe "approving" do
    test "another admin approves; validity starts at approval", c do
      grant = propose!(c)
      later = DateTime.add(F.now(), 3_600, :second)

      assert {:ok, active} = approve(c, c.approver, grant, later)
      assert active.lifecycle_state == :active
      assert active.approved_by == c.approver.user.user_id
      assert active.approved_at == later
      assert active.valid_from == later
      assert active.valid_until == DateTime.add(later, 86_400, :second)
      assert active.content_sha256 == grant.content_sha256
      assert {:ok, _grant} = use_grant(c, active, later)

      assert decisions(c, grant) == [:proposed, :approved]

      [_proposed, approved] =
        AutomationGrantDecisions.list(c.org, c.mission, grant.automation_grant_id)

      assert approved.subject.digest == grant.content_sha256
      assert c.proposer.user.user_id in approved.separated_from
      assert c.issuer.user.user_id in approved.separated_from
      assert approved.policy["separation_of_duties"] == true
    end

    test "the proposer can't approve their own grant", c do
      grant = propose!(c)

      assert {:error,
              {:automation_grant_self_approval_forbidden,
               %{because: "proposed", grantee: %{name: "Nightly planner"}}}} =
               approve(c, c.proposer, grant)

      assert decisions(c, grant) == [:proposed]
    end

    test "a person accountable for the service can't approve its grant", c do
      grant = propose!(c)
      service_id = c.service.service_identity_id

      assert {:error,
              {:automation_grant_self_approval_forbidden,
               %{because: "accountable", grantee: %{id: ^service_id}}}} =
               approve(c, c.issuer, grant)
    end

    test "a service with nobody on record can't have its grant approved by anyone", c do
      grant = propose!(c)
      id = c.service.service_identity_id

      # The accountables table is append-only (#436): the test-only purge, on for this delete only.
      Cadence.ServiceIdentityFixtures.forget_accountables!(id)

      assert {:error, {:automation_grant_approver_authors_unknown, %{service: %{id: ^id}}}} =
               approve(c, c.approver, grant)
    end

    test "only a person approves, even a service holding organization_admin", c do
      grant = propose!(c)

      assert {:error, :authenticated_user_required} = approve(c, admin_service(c), grant)
      assert {:error, :forbidden} = approve(c, c.member, grant)
    end

    test "a setting changed since the proposal refuses the approval", c do
      grant = propose!(c)
      policy = ActivationPolicy.load(c.org, c.mission)

      assert {:ok, _} =
               ActivationPolicy.save(c.proposer, c.mission, policy.token, %{
                 "value" => %{"approval_requirement" => "direct"}
               })

      assert {:error, {:approval_policy_changed, %{kind: "automation_grants"}}} =
               approve(c, c.approver, grant)
    end

    test "approval is at the hash the approver read", c do
      grant = propose!(c)

      assert {:error, :stale_automation_grant_hash} =
               approve(c, c.approver, %{grant | content_sha256: String.duplicate("0", 64)})
    end

    test "an undecided proposal expires after 72 hours and can't be approved", c do
      grant = propose!(c)
      late = DateTime.add(F.now(), 72 * 3600, :second)

      assert AutomationGrant.effective_state(grant, late) == :expired

      assert {:error, {:automation_grant_not_proposed, %{state: :expired} = details}} =
               approve(c, c.approver, grant, late)

      refute Map.has_key?(details, :decided_by)
    end
  end

  describe "rejecting" do
    test "needs a reason, and a rejected proposal can't be approved later", c do
      grant = propose!(c)

      assert {:error, :automation_grant_rejection_reason_required} =
               AutomationGrants.reject(c.approver, c.mission, grant.automation_grant_id, " ",
                 now: F.now()
               )

      assert {:ok, rejected} =
               AutomationGrants.reject(
                 c.approver,
                 c.mission,
                 grant.automation_grant_id,
                 "Too broad",
                 now: F.now()
               )

      assert %{lifecycle_state: :rejected, ending: %{reason: "Too broad"}} = rejected
      approver_id = c.approver.user.user_id

      assert {:error,
              {:automation_grant_not_proposed,
               %{state: :rejected, decided_by: ^approver_id, decided_at: %DateTime{}}}} =
               approve(c, c.third, grant)

      assert decisions(c, grant) == [:proposed, :rejected]
    end
  end

  describe "revoking" do
    test "one admin, at once, with or without a reason; the service stops", c do
      grant = active!(c)

      assert {:ok, revoked} =
               AutomationGrants.revoke(c.third, c.mission, grant.automation_grant_id, nil, nil)

      assert %{lifecycle_state: :revoked, ending: %{reason: nil}} = revoked
      assert {:error, :automation_grant_revoked} = use_grant(c, grant)
      assert decisions(c, grant) == [:proposed, :approved, :revoked]
    end

    test "revoke works while a widening is proposed, and withdraws it", c do
      grant = active!(c)
      widening = propose!(c, %{maximum_contacts: 8, replaces_grant_id: grant.automation_grant_id})

      assert {:ok, _revoked} =
               AutomationGrants.revoke(
                 c.third,
                 c.mission,
                 grant.automation_grant_id,
                 nil,
                 "Switch it off"
               )

      assert {:ok, %{lifecycle_state: :withdrawn} = withdrawn} =
               AutomationGrants.fetch(c.org, c.mission, widening.automation_grant_id)

      assert withdrawn.ending.by == c.third.user.user_id
      assert decisions(c, widening) == [:proposed, :withdrawn]

      assert {:error, {:automation_grant_not_proposed, %{state: :withdrawn}}} =
               approve(c, c.approver, widening)
    end

    # api-ops on #497: a retried revoke never reads as refused after the switch-off committed.
    test "revoking again answers the revoked grant and records nothing more", c do
      grant = active!(c)

      revoke = fn ->
        AutomationGrants.revoke(c.third, c.mission, grant.automation_grant_id, nil, nil)
      end

      assert {:ok, first} = revoke.()
      assert {:ok, again} = revoke.()
      assert again.lifecycle_state == :revoked
      assert again.ending == first.ending
      assert decisions(c, grant) == [:proposed, :approved, :revoked]
    end

    test "only a person revokes", c do
      grant = active!(c)

      assert {:error, :authenticated_user_required} =
               AutomationGrants.revoke(
                 admin_service(c),
                 c.mission,
                 grant.automation_grant_id,
                 nil,
                 nil
               )
    end
  end

  describe "widening" do
    test "a widening is a new proposal; its approval supersedes the old grant", c do
      grant = active!(c)
      widening = propose!(c, %{maximum_contacts: 8, replaces_grant_id: grant.automation_grant_id})

      assert {:ok, %{lifecycle_state: :active}} = approve(c, c.third, widening)

      assert {:ok, %{lifecycle_state: :revoked, ending: %{by: revoked_by}} = old} =
               AutomationGrants.fetch(c.org, c.mission, grant.automation_grant_id)

      assert revoked_by == c.third.user.user_id
      assert old.ending.reason =~ widening.automation_grant_id
    end

    test "the replaced grant's proposer can't approve the widening", c do
      grant = active!(c)

      assert {:ok, widening} =
               AutomationGrants.issue(
                 c.third,
                 c.mission,
                 F.grant_attrs(c.service, %{
                   maximum_contacts: 8,
                   replaces_grant_id: grant.automation_grant_id
                 }),
                 now: F.now()
               )

      assert {:error, {:automation_grant_self_approval_forbidden, %{because: "proposed"}}} =
               approve(c, c.proposer, widening)
    end
  end

  describe "narrowing (every field, strictly)" do
    @narrower [
      {"allowed_actions", %{allowed_actions: [:plan, :repair]}},
      {"maximum_horizon_seconds", %{maximum_horizon_seconds: 1_800}},
      {"maximum_contacts", %{maximum_contacts: 2}},
      {"maximum_execution_concurrency", %{maximum_execution_concurrency: 1}},
      {"maximum_estimated_cost_micros", %{maximum_estimated_cost_micros: 100}},
      {"validity_seconds", %{validity_seconds: 3_600}}
    ]

    @wider [
      {"allowed_actions",
       %{allowed_actions: [:plan, :repair, :submit, :approve, :execute, :bogus]}},
      {"maximum_horizon_seconds", %{maximum_horizon_seconds: 7_200}},
      {"maximum_contacts", %{maximum_contacts: 6}},
      {"maximum_execution_concurrency", %{maximum_execution_concurrency: 3}},
      {"maximum_estimated_cost_micros", %{maximum_estimated_cost_micros: 600}},
      {"currency", %{currency: "EUR"}},
      {"validity_seconds", %{validity_seconds: 90_000}},
      {"service_identity_id", %{"service_identity_id" => "svc-other"}},
      {"surprise", %{"surprise" => 1}}
    ]

    for {field, change} <- @narrower do
      test "narrowing #{field} takes effect at once", c do
        grant = active!(c)

        assert {:ok, narrowed} =
                 narrow(c, grant, unquote(Macro.escape(change)))

        assert narrowed.lifecycle_state == :active
        assert narrowed.content_sha256 != grant.content_sha256
        assert decisions(c, grant) == [:proposed, :approved, :narrowed]

        [_, _, narrowing] =
          AutomationGrantDecisions.list(c.org, c.mission, grant.automation_grant_id)

        assert narrowing.subject.previous_digest == grant.content_sha256
        assert narrowing.subject.digest == narrowed.content_sha256
      end
    end

    for {field, change} <- @wider do
      test "a wider #{field} isn't narrowing", c do
        grant = active!(c)

        assert {:error, {:automation_grant_not_narrower, %{fields: [unquote(field)]}}} =
                 narrow(c, grant, unquote(Macro.escape(change)))

        assert decisions(c, grant) == [:proposed, :approved]
      end
    end

    test "the same values aren't a narrowing", c do
      grant = active!(c)

      assert {:error, :automation_grant_narrow_unchanged} =
               narrow(c, grant, %{
                 maximum_contacts: 5
               })
    end

    test "a narrowed grant can't then be approved at its old hash", c do
      grant = active!(c)

      assert {:ok, _narrowed} =
               narrow(c, grant, %{
                 maximum_contacts: 2
               })

      assert {:error, {:automation_grant_not_proposed, %{state: :active}}} =
               approve(c, c.third, grant)
    end
  end

  # ca-security: a revoke waits for in-flight uses, and the next use sees it. The sandbox runs
  # every process on one connection, so a true two-process race can't block here; this pins the
  # locks that make it so in production: use reads the row FOR SHARE, revoke takes it FOR UPDATE.
  describe "concurrency" do
    test "use takes the grant FOR SHARE; revoke and narrow take it FOR UPDATE", c do
      grant = active!(c)

      {use_sql, {:ok, _}} = capture_sql(fn -> use_grant(c, grant) end)
      assert Enum.any?(use_sql, &(&1 =~ "automation_grants" and &1 =~ "FOR SHARE"))

      {narrow_sql, {:ok, _}} = capture_sql(fn -> narrow(c, grant, %{maximum_contacts: 4}) end)
      assert Enum.any?(narrow_sql, &(&1 =~ "automation_grants" and &1 =~ "FOR UPDATE"))

      {revoke_sql, {:ok, _}} =
        capture_sql(fn ->
          AutomationGrants.revoke(c.third, c.mission, grant.automation_grant_id, nil, nil)
        end)

      assert Enum.any?(revoke_sql, &(&1 =~ "automation_grants" and &1 =~ "FOR UPDATE"))
      assert {:error, :automation_grant_revoked} = use_grant(c, grant)
    end
  end

  # fe-ops and lead on #497: one lock order for every grant path, the replaced grant first.
  describe "lock order" do
    test "approving a widening locks the grant it replaces before the widening", c do
      grant = active!(c)
      widening = propose!(c, %{maximum_contacts: 8, replaces_grant_id: grant.automation_grant_id})

      {queries, {:ok, _}} = capture_queries(fn -> approve(c, c.third, widening) end)

      locked =
        for {sql, params} <- queries,
            sql =~ "automation_grants" and sql =~ "FOR UPDATE",
            id <- params,
            id in [grant.automation_grant_id, widening.automation_grant_id],
            do: id

      # The replaced grant is locked first, as revoke does (the grant, then its proposals).
      assert [first | _] = locked
      assert first == grant.automation_grant_id
      assert widening.automation_grant_id in locked

      assert {:ok, %{lifecycle_state: :revoked}} =
               AutomationGrants.fetch(c.org, c.mission, grant.automation_grant_id)
    end
  end

  test "the flags say policy_changed when the setting changed since the proposal", c do
    grant = propose!(c)
    policy = ActivationPolicy.load(c.org, c.mission)

    assert {:ok, _} =
             ActivationPolicy.save(c.proposer, c.mission, policy.token, %{
               "value" => %{"approval_requirement" => "direct"}
             })

    assert {"policy_changed", nil} =
             AutomationGrantReview.viewer_block(
               c.approver,
               grant,
               F.now()
             )
  end

  defp capture_queries(fun) do
    me = self()
    handler = "grant-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, meta, _cfg ->
        if self() == me, do: send(me, {:query, meta.query, meta.params || []})
      end,
      nil
    )

    try do
      result = fun.()
      {drain_queries([]), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain_queries(acc) do
    receive do
      {:query, sql, params} -> drain_queries([{sql, params} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp capture_sql(fun) do
    me = self()
    handler = "grant-sql-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, meta, _cfg -> if self() == me, do: send(me, {:sql, meta.query}) end,
      nil
    )

    try do
      result = fun.()
      {drain_sql([]), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain_sql(acc) do
    receive do
      {:sql, query} -> drain_sql([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "the content hash (#108)" do
    test "golden: the layout carries validity_seconds, not the window" do
      grant =
        AutomationGrant.new(%{
          automation_grant_id: "automation_grant_golden",
          organization_id: "org-golden",
          mission_id: "mission-golden",
          service_identity_id: "svc-golden",
          fleet_planning_policy_id: "fleet_planning_policy_golden",
          fleet_planning_policy_version: 1,
          allowed_actions: [:plan, :submit],
          maximum_horizon_seconds: 3_600,
          maximum_contacts: 5,
          maximum_estimated_cost_micros: 500,
          currency: "USD",
          maximum_execution_concurrency: 2,
          validity_seconds: 86_400,
          proposed_by: "proposer",
          proposed_at: F.now(),
          proposal_expires_at: DateTime.add(F.now(), 72 * 3600, :second),
          approval_reason: "Golden"
        })

      refute Map.has_key?(AutomationGrant.content_document(grant), "valid_from")
      assert AutomationGrant.content_document(grant)["validity_seconds"] == 86_400
      assert grant.content_sha256 == golden_sha256()
    end

    test "a row whose hash isn't today's layout is refused at use, never trusted", c do
      grant = active!(c)
      id = grant.automation_grant_id

      Repo.update_all(from(r in AutomationGrantRow, where: r.automation_grant_id == ^id),
        set: [content_sha256: String.duplicate("a", 64)]
      )

      assert {:error, :automation_grant_hash_mismatch} = use_grant(c, grant)
    end
  end

  # Pinned from the layout above (#283); a change here is a #108 layout change.
  defp golden_sha256, do: "2402591ca30cae66b3402afc7c0aa2fe88bb3683ee70519687caa8d037aab287"

  defp direct!(c) do
    policy = ActivationPolicy.load(c.org, c.mission)

    assert {:ok, _} =
             ActivationPolicy.save(c.proposer, c.mission, policy.token, %{
               "value" => %{"approval_requirement" => "direct"}
             })
  end

  # A service identity holding organization_admin: still refused (person-only).
  defp admin_service(c) do
    %Scope{
      actor_kind: :service,
      organization_id: c.org,
      organization: c.organization,
      service_identity: %{c.service | capabilities: [:organization_admin]},
      capabilities: MapSet.new([:organization_admin])
    }
  end
end
