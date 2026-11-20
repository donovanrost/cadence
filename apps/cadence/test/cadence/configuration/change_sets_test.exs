defmodule Cadence.Configuration.ChangeSetsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Comms.GroundStationStore
  alias Cadence.Configuration.{Access, ChangeSetStore, Ledger, Submission}
  alias Cadence.Control.Configuration
  alias Cadence.Organizations
  alias Cadence.Platform.ScopedReadUpdates

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission()

    %{
      org: org,
      mission: mission,
      alice: member_scope(org, :member, "Alice"),
      bob: member_scope(org, :member, "Bob")
    }
  end

  describe "with direct approval" do
    setup do
      on_exit(with_approval_required(false))
      :ok
    end

    test "stage then submit applies the set as r2", %{alice: alice, mission: mission} = ctx do
      assert {:ok, %{head: %{revision: 1, kind: :baseline}, change_set: nil}} =
               Configuration.current(alice, mission)

      assert {:ok, staged} =
               Configuration.stage(alice, mission, %{summary: "Add Svalbard"}, [
                 station_op("Svalbard")
               ])

      assert %{staged_count: 1, base_revision: 1, entity_ids: [station_id]} = staged

      assert {:ok, %{change_set: set}} = Configuration.current(alice, mission)
      assert %{state: :open, staged_count: 1, version: version} = set
      assert [%{summary: "Add Svalbard", author: %{name: "Alice"}}] = set.changes
      assert {:error, :ground_station_not_found} = fetch_station(ctx, station_id)

      assert {:ok, %{state: :applied, revision: 2, staged_count: 1, runtime: :not_applicable}} =
               Configuration.submit(alice, mission, set.id, %{
                 reason: "Add the Svalbard station",
                 expected_version: version
               })

      assert {:ok, %{display_name: "Svalbard"}} = fetch_station(ctx, station_id)

      assert {:ok, %{head: %{revision: 2, live: true}, change_set: nil}} =
               Configuration.current(alice, mission)

      assert {:ok, revision} = Configuration.get_revision(alice, mission, 2)

      assert %{
               kind: :change_set,
               reason: "Add the Svalbard station",
               applied_by: %{name: "Alice"}
             } = revision

      assert [%{kind: "ground_station", op: :create, before: nil}] = revision.entries

      assert {:ok, [%{revision: 2}, %{revision: 1}]} =
               Configuration.list_revisions(alice, mission)
    end

    test "submit requires a reason and the current version", %{alice: alice, mission: mission} do
      {:ok, staged} =
        Configuration.stage(alice, mission, %{summary: "Add"}, [station_op("Inuvik")])

      assert {:error, :reason_required} =
               Configuration.submit(alice, mission, staged.change_set_id, %{
                 reason: "short",
                 expected_version: staged.version
               })

      assert {:error, :change_set_changed} =
               Configuration.submit(alice, mission, staged.change_set_id, %{
                 reason: "Long enough reason",
                 expected_version: staged.version - 1
               })
    end

    test "a value changed outside the set is a conflict until rebased", ctx do
      %{alice: alice, mission: mission} = ctx
      station_id = applied_station(ctx, "Kiruna")

      {:ok, staged} =
        Configuration.stage(alice, mission, %{summary: "Rename"}, [
          %{
            kind: "ground_station",
            action: :update,
            entity_id: station_id,
            changes: [%{path: "display_name", value: "Kiruna 2"}]
          }
        ])

      {:ok, _} =
        GroundStationStore.update_ground_station(ctx.org, mission, station_id, %{
          display_name: "Esrange"
        })

      assert {:error, {:checks_failed, preview}} =
               Configuration.submit(alice, mission, staged.change_set_id, params(staged))

      assert %{verdict: :no_go} = preview
      conflicts = Enum.find(preview.checks, &(&1.key == "conflicts"))

      assert [%{reason: :value_changed, op_id: op_id, paths: [path]}] = conflicts.items

      assert %{
               path: "display_name",
               base: "Kiruna",
               live: "Esrange",
               staged: "Kiruna 2",
               changed_in: :outside,
               changed_by: nil
             } = path

      assert {:ok, %{version: version}} = Configuration.rebase(alice, mission, op_id, :keep_mine)

      assert {:ok, %{state: :applied, revision: 3}} =
               Configuration.submit(alice, mission, staged.change_set_id, %{
                 reason: "Rename after rebase",
                 expected_version: version
               })

      assert {:ok, %{display_name: "Kiruna 2"}} = fetch_station(ctx, station_id)
    end

    test "invalid ops are refused with field errors", %{alice: alice, mission: mission} do
      assert {:error, {:invalid_op, 0, [%{path: "display_name"} | _]}} =
               Configuration.stage(alice, mission, %{summary: "Bad"}, [station_op(nil)])

      assert {:error, {:invalid_op, 0, [%{path: "kind"}]}} =
               Configuration.stage(alice, mission, %{summary: "Bad"}, [
                 %{kind: "nope", action: :create}
               ])

      assert {:ok, %{change_set: nil}} = Configuration.current(alice, mission)
    end

    test "another author's staged path blocks; the same author's restage replaces it", ctx do
      %{alice: alice, bob: bob, mission: mission} = ctx
      station_id = applied_station(ctx, "Hartebeesthoek")

      rename = fn value ->
        [
          %{
            kind: "ground_station",
            action: :update,
            entity_id: station_id,
            changes: [%{path: "region", value: value}]
          }
        ]
      end

      {:ok, _} = Configuration.stage(alice, mission, %{summary: "Region"}, rename.("Africa"))

      {:ok, _} =
        Configuration.stage(
          alice,
          mission,
          %{summary: "Region again"},
          rename.("Southern Africa")
        )

      assert {:error,
              {:path_already_staged,
               %{path: "region", value: "Southern Africa", author: %{"name" => "Alice"}}}} =
               Configuration.stage(bob, mission, %{summary: "Region"}, rename.("ZA"))

      {:ok, %{change_set: set}} = Configuration.current(alice, mission)
      assert [%{summary: "Region again"}] = set.changes
      assert [%{summary: "Region"}] = set.withdrawn
    end

    test "withdraw and discard", %{alice: alice, bob: bob, mission: mission} do
      {:ok, a} = Configuration.stage(alice, mission, %{summary: "A"}, [station_op("A")])
      {:ok, b} = Configuration.stage(bob, mission, %{summary: "B"}, [station_op("B")])

      assert {:error, :forbidden} = Configuration.withdraw(bob, mission, a.change_id)
      assert {:ok, %{version: version}} = Configuration.withdraw(bob, mission, b.change_id)

      assert {:ok, %{discarded: 1, remaining: 0, state: "discarded"}} =
               Configuration.discard(alice, mission, a.change_set_id, version)

      assert {:ok, %{change_set: nil}} = Configuration.current(alice, mission)
    end

    # lead/ux 11-16: a set left with nothing staged closes, as a discard of everything does.
    test "withdrawing the last change closes the set; the next stage opens a fresh one",
         %{alice: alice, bob: bob, mission: mission} do
      {:ok, a} = Configuration.stage(alice, mission, %{summary: "A"}, [station_op("A")])
      {:ok, b} = Configuration.stage(bob, mission, %{summary: "B"}, [station_op("B")])

      # One of two withdrawn: the set stays open.
      assert {:ok, %{state: "open"}} = Configuration.withdraw(bob, mission, b.change_id)

      # The last one withdrawn: closed, with closed_at, the same terminal state as a discard.
      assert {:ok, %{state: "discarded"}} = Configuration.withdraw(alice, mission, a.change_id)
      assert {:ok, %{change_set: nil}} = Configuration.current(alice, mission)

      assert %{closed_at: %DateTime{}} =
               Repo.get(Cadence.Configuration.ChangeSetRow, a.change_set_id)

      {:ok, c} = Configuration.stage(alice, mission, %{summary: "C"}, [station_op("C")])
      refute c.change_set_id == a.change_set_id
    end

    test "compare folds revisions per entity", ctx do
      %{alice: alice, mission: mission} = ctx
      station_id = applied_station(ctx, "Punta Arenas")

      {:ok, staged} =
        Configuration.stage(alice, mission, %{summary: "Region"}, [
          %{
            kind: "ground_station",
            action: :update,
            entity_id: station_id,
            changes: [%{path: "region", value: "Patagonia"}]
          }
        ])

      {:ok, %{revision: 3}} =
        Configuration.submit(alice, mission, staged.change_set_id, params(staged))

      assert {:ok, [%{op: :create, revisions: [2, 3], fields: fields}]} =
               Configuration.compare(alice, mission, 1, 3)

      assert %{path: "region", before: nil, after: "Patagonia"} in fields

      assert {:ok, [%{revision: 3, op: :update}, %{revision: 2, op: :create}]} =
               Configuration.entity_history(alice, mission, "ground_station", station_id)
    end
  end

  describe "with independent approval" do
    setup do
      on_exit(with_approval_required(true))
      :ok
    end

    test "freezes in review; only a non-author approves",
         %{alice: alice, bob: bob, mission: mission} = ctx do
      {:ok, staged} =
        Configuration.stage(alice, mission, %{summary: "Add Fairbanks"}, [station_op("Fairbanks")])

      assert {:ok, %{state: :in_review, version: version}} =
               Configuration.submit(alice, mission, staged.change_set_id, params(staged))

      assert {:error, :frozen_in_review} =
               Configuration.stage(bob, mission, %{summary: "More"}, [station_op("More")])

      assert {:error, :reviewer_is_author} =
               Configuration.review(alice, mission, staged.change_set_id, :approve, %{
                 comment: "ok",
                 expected_version: version
               })

      assert {:ok, %{state: :applied, revision: 2}} =
               Configuration.review(bob, mission, staged.change_set_id, :approve, %{
                 comment: "Looks right",
                 expected_version: version
               })

      assert {:ok, %{approvals: [%{actor: %{name: "Bob"}, comment: "Looks right"}]}} =
               Configuration.get_revision(alice, mission, 2)

      [station_id] = staged.entity_ids
      assert {:ok, _} = fetch_station(ctx, station_id)
    end

    # #280: a service's changes count as its accountable people's. No console route lets a service
    # stage today; this keeps the review check right if a path ever does.
    test "a service's change set can't be reviewed by the person who issued the service",
         %{org: org, alice: alice, bob: bob, mission: mission} do
      {:ok, organization} = Organizations.fetch_organization(org)

      {:ok, %{service_identity: service}} =
        Auth.issue_service_identity(
          ServiceIdentity.new(%{
            organization_id: org,
            mission_id: mission,
            display_name: "Config bot",
            capabilities: [:mission_admin]
          }),
          alice
        )

      bot =
        Scope.new(%{
          organization_id: org,
          organization: organization,
          service_identity: service
        })

      {:ok, staged} =
        Configuration.stage(bot, mission, %{summary: "Bot"}, [station_op("Kiruna")])

      assert {:ok, %{state: :in_review, version: version}} =
               Configuration.submit(bot, mission, staged.change_set_id, params(staged))

      assert {:error, :reviewer_is_author} =
               Configuration.review(alice, mission, staged.change_set_id, :approve, %{
                 comment: "mine, through the bot",
                 expected_version: version
               })

      assert {:ok, %{state: :applied}} =
               Configuration.review(bob, mission, staged.change_set_id, :approve, %{
                 comment: "Looks right",
                 expected_version: version
               })
    end

    test "send back reopens the set", %{alice: alice, bob: bob, mission: mission} do
      {:ok, staged} =
        Configuration.stage(alice, mission, %{summary: "Add"}, [station_op("Weilheim")])

      {:ok, %{version: version}} =
        Configuration.submit(alice, mission, staged.change_set_id, params(staged))

      assert {:ok, %{state: :open}} =
               Configuration.review(bob, mission, staged.change_set_id, :send_back, %{
                 comment: "Wrong site",
                 expected_version: version
               })

      assert {:ok, %{change_set: %{state: :open, reviews: [%{decision: :sent_back}]}}} =
               Configuration.current(alice, mission)
    end
  end

  describe "a dropped connection during apply (qa #19)" do
    setup do
      on_exit(with_approval_required(false))
      :ok
    end

    test "reports the apply from the set's state, not the dropped call", %{alice: alice} = ctx do
      {:ok, staged} =
        Configuration.stage(alice, ctx.mission, %{summary: "Add Svalbard"}, [
          station_op("Svalbard")
        ])

      {:ok, before} = ChangeSetStore.fetch(ctx.mission, staged.change_set_id)
      # #261: landed/2 takes what this request wrote (its revision id, chosen before the apply).
      proof = %{
        actor: Access.actor(alice),
        act: :submit,
        version: before.version + 1,
        reason: params(staged).reason,
        policy: nil,
        revision_id: "config_revision-not-yet"
      }

      assert {:error, :apply_interrupted} = Submission.landed(before, proof)

      {:ok, %{state: :applied, revision: 2}} =
        Configuration.submit(alice, ctx.mission, staged.change_set_id, params(staged))

      {:ok, %{revision_id: landed_id}} = Ledger.fetch_revision(ctx.mission, 2)
      proof = %{proof | revision_id: landed_id}

      assert {:ok,
              %{
                state: :applied,
                revision: 2,
                staged_count: 1,
                kinds: ["ground_station"],
                runtime: :not_applicable,
                activation_payload: nil
              }} = Submission.landed(before, proof)
    end
  end

  describe "preview" do
    test "runs in a rolled-back sandbox and publishes nothing",
         %{alice: alice, org: org, mission: mission} = ctx do
      ScopedReadUpdates.subscribe(:configuration_changed, org, mission)
      ScopedReadUpdates.subscribe(:spacecraft_configuration_changed, org, mission)

      spacecraft = %{
        kind: "spacecraft",
        action: :create,
        document: %{"display_name" => "EARENDIL-001", "scid" => 1}
      }

      assert {:ok,
              %{verdict: :go, diffs: [%{action: "create", entity_id: id, fields: fields}, _]}} =
               Configuration.preview(alice, mission, {:ops, [station_op("Inuvik"), spacecraft]})

      assert %{path: "display_name", before: nil, after: "Inuvik"} in fields
      assert {:error, :ground_station_not_found} = fetch_station(ctx, id)
      refute_receive _any, 50
    end
  end

  describe "authorization" do
    test "a non-member can't read or stage", %{org: org, mission: mission} do
      outsider = member_scope(org) |> Map.put(:organization_membership, nil)

      assert {:error, :forbidden} = Configuration.current(outsider, mission)

      assert {:error, :forbidden} =
               Configuration.stage(outsider, mission, %{summary: "x"}, [station_op("x")])
    end

    test "permissions list the config capabilities", %{alice: alice, org: org, mission: mission} do
      assert {:ok, permissions} = Configuration.permissions(alice, mission)
      assert "config.stage" in permissions
      refute "config.discard_any" in permissions

      admin = member_scope(org, :organization_admin)
      assert {:ok, admin_permissions} = Configuration.permissions(admin, mission)
      assert "config.discard_any" in admin_permissions
    end
  end

  defp applied_station(%{alice: alice, mission: mission}, name) do
    restore = with_approval_required(false)

    {:ok, staged} =
      Configuration.stage(alice, mission, %{summary: "Add #{name}"}, [station_op(name)])

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, params(staged))

    restore.()
    [station_id] = staged.entity_ids
    station_id
  end

  defp params(staged), do: %{reason: "Reason for this change", expected_version: staged.version}

  defp fetch_station(%{org: org, mission: mission}, id),
    do: GroundStationStore.fetch_ground_station(org, mission, id)
end
