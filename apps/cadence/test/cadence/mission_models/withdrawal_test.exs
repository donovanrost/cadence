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
  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.CompositionFixtures
  alias Cadence.Control.Activations, as: ControlActivations

  alias Cadence.Control.{
    Configuration,
    ConfigurationSelections,
    ModelApprovalGate,
    ModelWithdrawal,
    WithdrawnPins
  }

  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Compositions, DecisionRow, RevisionRow, Selection}
  alias Cadence.Reads.{SpacecraftDirectory, WithdrawnApprovalAttention}

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

  describe "the gate's backstop" do
    test "never grandfathers a withdrawn revision for a craft the generation changes", c do
      {:ok, _} = withdraw(c, c.model)
      running = %{"craft-1" => %{"mission_model" => %{"revision_id" => c.model}, "v" => 1}}
      changed = %{"craft-1" => %{"mission_model" => %{"revision_id" => c.model}, "v" => 2}}
      model = c.model

      assert {:error, {:mission_model_revision_not_approved, [^model]}} =
               ModelApprovalGate.check(c.org, c.mid, changed, running, nil)

      # An untouched craft keeps running it: nothing auto-stops (§5).
      assert :ok = ModelApprovalGate.check(c.org, c.mid, running, running, nil)
    end
  end

  describe "the apply's own check" do
    test "a recorded withdrawn answer still refuses: no fallback to the catalog's revision", c do
      {:ok, _} = withdraw(c, c.model)
      recorded = %{c.composition => "withdrawn"}

      assert {:error, {:restage_needed, [entry]}} =
               ConfigurationSelections.check(c.org, c.mid, recorded, [
                 c.catalog.catalog_revision_id
               ])

      assert %{current_revision_id: nil, current_reason: "withdrawn", decision: %{}} = entry
    end
  end

  describe "the reads (E2b)" do
    test "the directory row and the attention item name the decision; both clear when moved", c do
      configure!(c)
      {:ok, _} = withdraw(c, c.model)
      id = c.craft.spacecraft_id

      {:ok, %{spacecraft: rows}} = SpacecraftDirectory.page(c.org, c.mid)
      row = Enum.find(rows, &(&1.id == id))

      assert %{
               revision_id: revision,
               decision: %{kind: "withdrawn", reason: "Limits were wrong"},
               # U109's way out: nothing else approved is left, so it's null.
               earlier_approved: nil
             } = row.approval_withdrawn

      assert revision == c.model

      assert [item] = WithdrawnApprovalAttention.items(c.org, c.mid)
      assert item.source == "model_approval_withdrawn"
      assert item.spacecraft_id == id
      assert item.severity == "crit"

      assert %{
               revision_id: ^revision,
               kind: "withdrawn",
               reason: "Limits were wrong",
               composition: %{},
               earlier_approved: nil
             } = item.withdrawal

      assert %{open: 1} = WithdrawnApprovalAttention.counts(c.org, c.mid)
    end
  end

  describe "an unchanged pin on a withdrawn composition (commanding's review of #881)" do
    test "a change set touching its craft for another reason is refused, not regenerated", c do
      configure!(c)
      profile = profile!(c)
      {:ok, _} = withdraw(c, c.model)

      {:ok, staged} =
        Configuration.stage(c.scope, c.mid, %{summary: "Frame size"}, [
          %{
            kind: "spacecraft_profile",
            action: :update,
            entity_id: profile,
            changes: [%{path: "frame_parameters.frame_size", value: 1024}]
          }
        ])

      # A profile change regenerates the craft's entry without a catalog change, so it never reaches
      # the selection check; the preview's HOLD and the gate refuse the withdrawn revision.
      model = c.model
      # The preview says why first: a blocking HOLD naming the withdrawn revision and decision.
      {:ok, preview} = Configuration.preview(c.scope, c.mid, staged.change_set_id)
      assert preview.selections[c.composition] == "withdrawn"

      assert %{verdict: :hold, items: items} =
               Enum.find(preview.checks, &(&1.key == "compatibility"))

      assert %{blocking: true, spacecraft_ids: [craft], details: details, sentence: sentence} =
               Enum.find(items, &(&1.reason == :model_approval_withdrawn))

      assert craft == c.craft.spacecraft_id
      assert details.revision_id == c.model
      assert details.decision.reason == "Limits were wrong"
      assert sentence =~ "which is no longer approved"
      # The submit stops at that blocking HOLD; the gate's own check is the backstop at apply.
      assert {:error, {:holds_blocking, _preview}} = submit(c, staged)
      assert {:ok, %{status: :withdrawn}} = MissionModels.fetch_revision(c.org, c.mid, model)
    end
  end

  # An active generation for the craft on the fixture's catalog (the paths test's configure!/2).
  defp configure!(c) do
    {:ok, mission} = Cadence.Missions.fetch_mission(c.org, c.mid)
    current = Drafts.snapshot(mission, c.craft)

    endpoint =
      Cadence.SourceEndpoints.list_source_endpoints(c.org, c.mid)
      |> Enum.find(&(&1.spacecraft_id == c.craft.spacecraft_id))

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.catalog.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42],
        "telemetry_source_endpoint_id" => endpoint && endpoint.source_endpoint_id
      })

    :ok = Fixtures.change_set_switches!(c.org, c.mid, c.craft.spacecraft_id, document)
    {:ok, _} = Drafts.save(c.scope, c.mid, c.craft.spacecraft_id, current.token, document)
    token = Drafts.snapshot(mission, c.craft).token

    {:ok, request} = Review.request_many(c.scope, c.mid, %{c.craft.spacecraft_id => token})
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end

  defp profile!(c) do
    id = "profile-withdraw-#{System.unique_integer([:positive])}"
    {:ok, _} = apply!(c, [create_profile(c.composition) |> Map.put(:entity_id, id)])

    {:ok, _} =
      apply!(c, [
        %{
          kind: "spacecraft",
          action: :update,
          entity_id: c.craft.spacecraft_id,
          changes: [
            %{path: "spacecraft_type_id", value: id},
            %{path: "spacecraft_type_version", value: 1}
          ]
        }
      ])

    id
  end

  defp apply!(c, ops) do
    {:ok, staged} = Configuration.stage(c.scope, c.mid, %{summary: "Withdraw test"}, ops)
    {:ok, %{state: :applied} = applied} = submit(c, staged)
    {:ok, applied}
  end

  defp submit(c, staged),
    do:
      Configuration.submit(c.scope, c.mid, staged.change_set_id, %{
        reason: "Withdrawal test",
        expected_version: staged.version,
        acknowledged_holds: true
      })

  describe "Reads.WithdrawnPins.for_spacecraft/3 (commanding's HOLD, the state line, the attention item)" do
    test "names the craft whose active generation runs the withdrawn revision", c do
      configure!(c)
      id = c.craft.spacecraft_id
      assert WithdrawnPins.for_spacecraft(c.org, c.mid, [id]) == %{}

      {:ok, _} = withdraw(c, c.model)

      assert %{^id => pin} = WithdrawnPins.for_spacecraft(c.org, c.mid, [id, "not-a-craft"])
      assert pin.revision_id == c.model
      assert pin.composition_id == c.composition

      assert %{kind: "withdrawn", reason: "Limits were wrong", at: at, by: by} = pin.decision

      # C1 (Control.ActorRef): the fixture's admin isn't a member of the organization, so they're
      # named by neither id nor the stored name (the console API test names a member).
      assert by == %{kind: "user", id: nil, name: nil}
      assert pin.hold_basis == "#{c.model}:withdrawn:#{DateTime.to_iso8601(at)}"
      assert WithdrawnPins.for_spacecraft(c.org, c.mid, []) == %{}
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
