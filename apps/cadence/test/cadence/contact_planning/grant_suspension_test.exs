defmodule Cadence.ContactPlanning.GrantSuspensionTest do
  @moduledoc """
  #499 (the director on #283; ca-security, api-ops 11-20): tightening a mission's approval setting
  to 'independent' suspends its automation grants that went active on one approval, until a
  second, separated approval resumes them. The save lists them first (409 with a digest, nothing
  written); it suspends them in its own transaction; a suspended grant authorizes nothing;
  resume follows the setting in force; every act is recorded.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.AutomationGrantFixtures, as: F

  alias Cadence.ContactPlanning.{
    AutomationGrantDecisions,
    AutomationGrantReview,
    AutomationGrants,
    GrantSuspension
  }

  alias Cadence.Governance.{ActivationPolicy, ApprovalTightening}
  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Platform.ScopedSettings
  alias Ecto.Adapters.SQL.Sandbox

  setup context do
    c = F.setup!("grant-suspension")

    # 'direct' with overrides allowed: a grant is active at once, on its proposer's approval. The
    # lock-order test keeps the default and takes no governance lock in its own connection (the
    # sandbox holds every lock it took until the test ends).
    unless context[:no_setting_save], do: {:ok, _} = organization(c, "direct", true)
    c
  end

  describe "a tightening suspends single-approval grants" do
    test "a mission save lists them first (409, nothing written), then suspends with the digest",
         c do
      grant = issue!(c)
      assert grant.lifecycle_state == :active

      assert {:error, {:approval_tightening_suspends_grants, %{grants: [listed], digest: digest}}} =
               pin(c, c.approver, "independent")

      assert listed.id == grant.automation_grant_id
      assert listed.mission == %{id: c.mission, name: c.mission}
      assert listed.service == %{id: c.service.service_identity_id, name: "Nightly planner"}
      assert listed.allowed_actions == Enum.map(grant.allowed_actions, &Atom.to_string/1)
      assert listed.valid_until == grant.valid_until

      # Nothing written: the setting is unchanged and the grant still works.
      assert requirement(c) == "direct"
      assert {:ok, _} = use_grant(c, grant)

      assert {:ok, revision} = pin(c, c.approver, "independent", acknowledged: digest)
      assert requirement(c) == "independent"

      suspended = fetch!(c, grant)
      assert suspended.lifecycle_state == :suspended
      assert suspended.content_sha256 == grant.content_sha256
      assert suspended.valid_until == grant.valid_until

      assert %{by: by, revision: rev, level: "mission"} = suspended.suspension
      assert by == c.approver.user.user_id
      assert rev == revision.revision_id

      assert {:error, {:automation_grant_not_active, %{state: :suspended}}} =
               use_grant(c, suspended)

      assert decisions(c, grant) == [:not_required, :suspended]
    end

    test "an organization save suspends the grants of the missions it tightens", c do
      grant = issue!(c)

      assert {:error, {:approval_tightening_suspends_grants, %{grants: [listed], digest: digest}}} =
               organization(c, "independent", true)

      assert listed.mission.id == c.mission
      assert {:ok, _} = organization(c, "independent", true, acknowledged: digest)

      assert %{lifecycle_state: :suspended, suspension: %{level: "organization"}} =
               fetch!(c, grant)
    end

    test "only active, unexpired, non-legacy grants approved alone are selected", c do
      approved_alone = issue!(c)
      expired = issue!(c, %{service: second_service!(c, "expired")})
      revoked = issue!(c, %{service: second_service!(c, "revoked")})
      legacy = issue!(c, %{service: second_service!(c, "legacy")})

      {:ok, _} =
        AutomationGrants.revoke(c.third, c.mission, revoked.automation_grant_id, nil, nil,
          now: F.now()
        )

      Repo.update_all(
        from(r in AutomationGrantRow,
          where: r.automation_grant_id == ^legacy.automation_grant_id
        ),
        set: [legacy_issue: true]
      )

      later = DateTime.add(F.now(), 3_600, :second)

      Repo.update_all(
        from(r in AutomationGrantRow,
          where: r.automation_grant_id == ^expired.automation_grant_id
        ),
        set: [
          valid_until: DateTime.add(later, -1, :second),
          valid_from: DateTime.add(later, -86_401, :second)
        ]
      )

      ids =
        c.org
        |> GrantSuspension.candidates([c.mission], later)
        |> Enum.map(& &1.automation_grant_id)

      assert ids == [approved_alone.automation_grant_id]
    end

    test "a grant approved by a second person under 'independent' isn't suspended", c do
      {:ok, _} = organization(c, "independent", true)

      {:ok, proposed} =
        AutomationGrants.issue(c.proposer, c.mission, F.grant_attrs(c.service), now: F.now())

      {:ok, separated} =
        AutomationGrants.approve(
          c.approver,
          c.mission,
          proposed.automation_grant_id,
          proposed.content_sha256,
          now: F.now()
        )

      assert separated.approval_policy["separation_of_duties"] == true
      assert GrantSuspension.candidates(c.org, [c.mission], F.now()) == []
    end

    test "a grant made between the preview and the save changes the digest: 409 again", c do
      issue!(c)
      {:error, {_code, %{digest: first}}} = pin(c, c.approver, "independent")
      second = issue!(c, %{service: second_service!(c, "late")})

      assert {:error, {:approval_tightening_suspends_grants, %{grants: grants, digest: digest}}} =
               pin(c, c.approver, "independent", acknowledged: first)

      assert digest != first
      assert second.automation_grant_id in Enum.map(grants, & &1.id)
      assert requirement(c) == "direct"
    end

    test "a settings save that rolls back after suspending suspends nothing", c do
      grant = issue!(c)
      {:error, {_code, %{digest: digest}}} = pin(c, c.approver, "independent")

      previous = Application.get_env(:cadence, :approval_tightening)
      Application.put_env(:cadence, :approval_tightening, __MODULE__.FailingTightening)
      on_exit(fn -> Application.put_env(:cadence, :approval_tightening, previous) end)

      assert {:error, :injected_after_suspending} =
               pin(c, c.approver, "independent", acknowledged: digest)

      assert requirement(c) == "direct"
      assert fetch!(c, grant).lifecycle_state == :active
      assert decisions(c, grant) == [:not_required]
    end

    test "loosening never resumes a suspended grant", c do
      grant = suspend!(c)
      assert {:ok, _} = pin(c, c.proposer, "direct")
      assert fetch!(c, grant).lifecycle_state == :suspended
    end
  end

  # api-ops: a missing registration would suspend nothing (fail open), so it's pinned.
  test "the approval setting's tightening hook is GrantSuspension" do
    assert ApprovalTightening.implementation() == GrantSuspension
  end

  # ca-security: with nothing registered, a tightening is refused (fail closed), not let through.
  test "a tightening save with no hook registered is refused, writing nothing", c do
    grant = issue!(c)
    previous = Application.get_env(:cadence, :approval_tightening)
    Application.delete_env(:cadence, :approval_tightening)
    on_exit(fn -> Application.put_env(:cadence, :approval_tightening, previous) end)

    assert {:error, :approval_tightening_unavailable} = pin(c, c.approver, "independent")
    assert requirement(c) == "direct"
    assert fetch!(c, grant).lifecycle_state == :active
  end

  describe "the acknowledgement digest" do
    # DECISIONS #108 / ca-security: a versioned, canonical layout, golden-pinned.
    test "is sha256 of [1, sorted [id, content_sha256, state]]" do
      grants = [
        %{automation_grant_id: "g-2", content_sha256: "b", lifecycle_state: :active},
        %{automation_grant_id: "g-1", content_sha256: "a", lifecycle_state: :active}
      ]

      # Golden: a change to the layout or the canonical encoding moves this value on purpose.
      assert GrantSuspension.digest(grants) ==
               "a67367c8aceb3bf74c6f239957c1906bb8322133f2276fd0c170feb17b3c92aa"

      assert GrantSuspension.digest(Enum.reverse(grants)) == GrantSuspension.digest(grants)

      refute GrantSuspension.digest([%{hd(grants) | lifecycle_state: :suspended} | tl(grants)]) ==
               GrantSuspension.digest(grants)
    end
  end

  describe "resume" do
    test "under 'independent' a separated org admin resumes; the original approver and the accountable don't",
         c do
      grant = suspend!(c)

      # The proposer approved it alone (it was 'direct'): refused as its approver.
      assert {:error, {:automation_grant_self_approval_forbidden, %{because: "approved"}}} =
               resume(c, c.proposer, grant)

      # The service's issuer is accountable for it (#280).
      assert {:error, {:automation_grant_self_approval_forbidden, %{because: "accountable"}}} =
               resume(c, c.issuer, grant)

      assert {:ok, resumed} = resume(c, c.third, grant)
      assert resumed.lifecycle_state == :active
      assert resumed.resumption.by == c.third.user.user_id
      assert resumed.approval_policy["separation_of_duties"] == true
      assert resumed.content_sha256 == grant.content_sha256
      assert resumed.valid_until == grant.valid_until
      assert {:ok, _} = use_grant(c, resumed)
      assert decisions(c, grant) == [:not_required, :suspended, :resumed]

      [_, _, record] = AutomationGrantDecisions.list(c.org, c.mission, grant.automation_grant_id)
      assert c.proposer.user.user_id in record.separated_from
    end

    test "under 'direct' (loosened again) the proposer may resume, as issuing anew would", c do
      grant = suspend!(c)
      assert {:ok, _} = pin(c, c.proposer, "direct")
      assert {:ok, %{lifecycle_state: :active}} = resume(c, c.proposer, grant)
    end

    test "a stale hash, an expired grant, a legacy grant and a grant not suspended are refused",
         c do
      grant = suspend!(c)

      assert {:error, :stale_automation_grant_hash} =
               AutomationGrantReview.resume(c.third, c.mission, grant.automation_grant_id, "0",
                 now: F.now()
               )

      later = DateTime.add(grant.valid_until, 1, :second)

      assert {:error, {:automation_grant_not_suspended, %{state: :expired}}} =
               AutomationGrantReview.resume(
                 c.third,
                 c.mission,
                 grant.automation_grant_id,
                 grant.content_sha256,
                 now: later
               )

      # Under 'independent' now, a new grant is a proposal: nothing to resume.
      proposed = issue!(c, %{service: second_service!(c, "proposed")})

      assert {:error, {:automation_grant_not_suspended, %{state: :proposed}}} =
               resume(c, c.third, proposed)

      Repo.update_all(
        from(r in AutomationGrantRow, where: r.automation_grant_id == ^grant.automation_grant_id),
        set: [legacy_issue: true]
      )

      assert {:error, {:automation_grant_legacy, _}} = resume(c, c.third, grant)
    end

    # api-ops: narrowing re-hashes; a resume at the old hash is stale, at the new one it works.
    test "narrowing a suspended grant keeps it suspended and moves the hash resume needs", c do
      grant = suspend!(c)

      assert {:ok, narrowed} =
               AutomationGrants.narrow(
                 c.third,
                 c.mission,
                 grant.automation_grant_id,
                 %{"maximum_contacts" => 2},
                 now: F.now()
               )

      assert narrowed.lifecycle_state == :suspended
      assert narrowed.content_sha256 != grant.content_sha256

      assert {:error, :stale_automation_grant_hash} = resume(c, c.third, grant)
      assert {:ok, %{lifecycle_state: :active}} = resume(c, c.third, narrowed)
    end
  end

  describe "a suspended grant" do
    test "can be revoked", c do
      grant = suspend!(c)

      assert {:ok, %{lifecycle_state: :revoked}} =
               AutomationGrants.revoke(c.third, c.mission, grant.automation_grant_id, nil, nil,
                 now: F.now()
               )
    end

    test "keeps its service's one live grant: a new one is a named 409, never a 500", c do
      grant = suspend!(c)
      {:ok, _} = pin(c, c.proposer, "direct")
      id = grant.automation_grant_id

      assert {:error, {:automation_grant_service_has_grant, %{grant_id: ^id, state: "suspended"}}} =
               AutomationGrants.issue(c.proposer, c.mission, F.grant_attrs(c.service),
                 now: F.now()
               )
    end
  end

  # ca-security / api-ops: issue reads the approval setting under its lock SHARED, so a grant
  # can't be made while a tightening save holds it exclusive (and slip past its list).
  @tag :no_setting_save
  test "issuing a grant waits for an open approval-setting save", c do
    parent = self()

    holder =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          ScopedSettings.with_lock(c.org, ActivationPolicy.section_id(), fn ->
            send(parent, :locked)

            receive do
              :release -> {:ok, :released}
            after
              10_000 -> {:ok, :timeout}
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert_receive :locked, 5_000

    issuer = Task.async(fn -> issue!(c) end)
    refute Task.yield(issuer, 300)

    send(holder.pid, :release)
    assert {:ok, :released} = Task.await(holder)
    assert %{lifecycle_state: :proposed} = Task.await(issuer)
  end

  defmodule FailingTightening do
    @moduledoc false
    @behaviour Cadence.Governance.ApprovalTightening

    alias Cadence.ContactPlanning.GrantSuspension

    @impl true
    def preview(org, ids, acknowledged, opts),
      do: GrantSuspension.preview(org, ids, acknowledged, opts)

    @impl true
    def apply(scope, org, ids, revision, level, opts) do
      {:ok, _suspended} = GrantSuspension.apply(scope, org, ids, revision, level, opts)
      {:error, :injected_after_suspending}
    end
  end

  # -- helpers ---------------------------------------------------------------------------------

  defp issue!(c, overrides \\ %{}) do
    {service, overrides} = Map.pop(overrides, :service, c.service)

    assert {:ok, grant} =
             AutomationGrants.issue(c.proposer, c.mission, F.grant_attrs(service, overrides),
               now: F.now()
             )

    grant
  end

  defp suspend!(c) do
    grant = issue!(c)
    {:error, {_code, %{digest: digest}}} = pin(c, c.approver, "independent")
    {:ok, _} = pin(c, c.approver, "independent", acknowledged: digest)
    fetch!(c, grant)
  end

  defp resume(c, scope, grant),
    do:
      AutomationGrantReview.resume(
        scope,
        c.mission,
        grant.automation_grant_id,
        grant.content_sha256,
        now: F.now()
      )

  defp pin(c, scope, requirement, opts \\ []) do
    current = ActivationPolicy.load(c.org, c.mission)

    ActivationPolicy.save(
      scope,
      c.mission,
      current.token,
      %{"value" => %{"approval_requirement" => requirement}},
      save_opts(opts)
    )
  end

  defp organization(c, requirement, allow_override, opts \\ []) do
    current = ActivationPolicy.load(c.org, nil)

    ActivationPolicy.save(
      c.proposer,
      nil,
      current.token,
      %{"value" => %{"approval_requirement" => requirement}, "allow_override" => allow_override},
      save_opts(opts)
    )
  end

  defp save_opts(opts),
    do: [acknowledged_suspensions: Keyword.get(opts, :acknowledged), now: F.now()]

  defp requirement(c),
    do: ActivationPolicy.load(c.org, c.mission).effective["approval_requirement"]

  defp fetch!(c, grant) do
    {:ok, grant} = AutomationGrants.fetch(c.org, c.mission, grant.automation_grant_id)
    grant
  end

  defp use_grant(c, grant),
    do:
      AutomationGrants.authorize(
        c.service_scope,
        c.mission,
        grant.automation_grant_id,
        :plan,
        %{horizon_seconds: 3_600},
        now: F.now()
      )

  defp decisions(c, grant),
    do:
      c.org
      |> AutomationGrantDecisions.list(c.mission, grant.automation_grant_id)
      |> Enum.map(& &1.decision)

  defp second_service!(c, name) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-#{name}-#{System.unique_integer([:positive])}",
        organization_id: c.org,
        mission_id: c.mission,
        display_name: "Planner #{name}",
        capabilities: [:mission_admin]
      })

    {:ok, issued} = Auth.issue_service_identity(identity, c.issuer)
    issued.service_identity
  end
end
