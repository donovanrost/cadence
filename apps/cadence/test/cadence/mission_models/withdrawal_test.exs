defmodule Cadence.MissionModels.WithdrawalTest do
  @moduledoc """
  E2 (#546; design §5, CB-15): withdrawing a composition's approval. With commanding's conditions
  (#546):
  - withdrawn is terminal, in the database too;
  - an older approval of the same composition is what staging selects next;
  - the lock order is ActivationLocks';
  - it takes the same authority as approving;
  - the decision is one append-only record, written with the status change.

  The next generation is refused at staging (NO-GO with the decision) and at apply
  (`restage_needed`, `current_reason: "withdrawn"`).
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.User
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.CompositionFixtures
  alias Cadence.Control.{Configuration, ConfigurationSelections, ModelWithdrawal}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Compositions, DecisionRow, RevisionRow, Selection}

  setup do
    org = "org-withdraw-#{System.unique_integer([:positive])}"
    mid = "mission-withdraw-#{System.unique_integer([:positive])}"
    {craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    scope = Fixtures.user_scope(org, "admin")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    model = catalog.mission_model_revision_id
    {:ok, %{composition_id: composition}} = Compositions.for_revision(org, mid, model)

    %{
      org: org,
      mid: mid,
      scope: scope,
      craft: craft,
      catalog: catalog,
      model: model,
      composition: composition
    }
  end

  defp withdraw(c, revision, opts \\ [operation_id: "op-1"]),
    do: ModelWithdrawal.withdraw(c.scope, c.mid, revision, "Limits were wrong", opts)

  defp records(revision),
    do: Repo.all(from(d in DecisionRow, where: d.revision_id == ^revision))

  describe "withdrawing an approved revision" do
    test "it becomes withdrawn, with exactly one withdrawn record naming the composition", c do
      assert {:ok, %{status: :withdrawn}} = withdraw(c, c.model)

      assert [record] = records(c.model)
      assert record.decision == "withdrawn"
      assert record.reason == "Limits were wrong"
      assert record.actor["id"] == c.scope.user.user_id
      assert record.composition_id == c.composition
      assert record.subject["composition"]["composition_id"] == c.composition
      assert record.operation_id == "op-1"
    end

    test "withdrawn is terminal: approve refuses it and the database refuses any move back", c do
      {:ok, _} = withdraw(c, c.model)

      assert {:error, :mission_model_revision_not_approvable} =
               MissionModels.approve_revision(c.scope, c.mid, c.model, "any-report")

      assert_raise Postgrex.Error, ~r/withdrawn is terminal/, fn ->
        Repo.update_all(from(r in RevisionRow, where: r.revision_id == ^c.model),
          set: [status: "approved"]
        )
      end
    end

    test "the record is append-only", c do
      {:ok, _} = withdraw(c, c.model)

      assert_raise Postgrex.Error, fn ->
        Repo.update_all(from(d in DecisionRow, where: d.revision_id == ^c.model),
          set: [reason: "Changed"]
        )
      end
    end

    test "the same operation replays; anything else is not withdrawable", c do
      {:ok, _} = withdraw(c, c.model)

      assert {:ok, {:replayed, %{status: :withdrawn}}} = withdraw(c, c.model)

      assert {:error, :mission_model_revision_not_withdrawable} =
               withdraw(c, c.model, operation_id: "op-2")

      assert [_one] = records(c.model)
    end

    test "only an approved revision, with a reason, by someone who may approve", c do
      candidate = CompositionFixtures.copy_revision!(ctx(c), "2")
      CompositionFixtures.set_status!([candidate], "candidate")

      assert {:error, :mission_model_revision_not_withdrawable} = withdraw(c, candidate)

      for blank <- [nil, "", "   "] do
        assert {:error, :mission_model_decision_reason_required} =
                 ModelWithdrawal.withdraw(c.scope, c.mid, c.model, blank)
      end

      operator =
        Scope.new(%{
          user:
            User.new(%{
              user_id: "operator-546",
              email: "operator-546@example.test",
              display_name: "Operator"
            }),
          organization_id: c.org
        })

      assert {:error, :forbidden} =
               ModelWithdrawal.withdraw(operator, c.mid, c.model, "Not mine to take back")

      assert records(c.model) == []
    end
  end

  describe "the next generation is refused" do
    test "selection answers withdrawn, and staging is a NO-GO naming the decision", c do
      {:ok, _} = withdraw(c, c.model)

      assert {:error, :withdrawn} = Selection.select(c.org, c.mid, c.composition)

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mid, {:ops, [create_profile(c.composition)]})

      assert %{
               items: [%{errors: [%{path: "composition_id", message: message, details: details}]}]
             } =
               Enum.find(checks, &(&1.key == "validation"))

      assert message =~ "is no longer approved"
      assert details.reason == "withdrawn"

      assert %{kind: "withdrawn", revision_id: revision, reason: "Limits were wrong"} =
               details.decision

      assert revision == c.model
    end

    test "an older approval of the same composition is selected; an in-flight apply restages",
         c do
      # An older compiler's revision of the same composition, approved; both versions runnable
      # (Selection's test-only list), so the original (version 2) is the newer.
      runnable = [runnable: ["1", "2"]]
      older = CompositionFixtures.copy_revision!(ctx(c), "1")
      CompositionFixtures.link!(ctx(c), c.composition, older)
      CompositionFixtures.approve!(older)
      newer = c.model

      assert {:ok, ^newer} = Selection.select(c.org, c.mid, c.composition, runnable)

      {:ok, _} = withdraw(c, newer)
      assert {:ok, ^older} = Selection.select(c.org, c.mid, c.composition, runnable)

      # A set submitted before the withdrawal recorded `newer`; its apply refuses, naming why.
      recorded = %{c.composition => newer}

      assert {:error, {:restage_needed, [entry]}} =
               ConfigurationSelections.check(
                 c.org,
                 c.mid,
                 recorded,
                 [c.catalog.catalog_revision_id],
                 runnable
               )

      assert %{
               recorded_revision_id: ^newer,
               current_revision_id: ^older,
               current_reason: "withdrawn",
               decision: %{kind: "withdrawn", reason: "Limits were wrong"}
             } = entry
    end
  end

  defp ctx(c), do: %{org: c.org, mid: c.mid, revision_id: c.model, catalog: c.catalog}

  defp create_profile(composition),
    do: %{
      kind: "spacecraft_profile",
      action: :create,
      entity_id: "profile-withdraw-#{System.unique_integer([:positive])}",
      document: %{
        "display_name" => "Withdrawn pin",
        "downlink_protocol" => "tm",
        "uplink_protocol" => "tc",
        "composition_id" => composition,
        "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
      }
    }
end
