defmodule Cadence.Configuration.CompositionPinsTest do
  @moduledoc """
  D3 (#544; design §3): profiles and per-craft overrides pin a mission composition, through change
  sets only. An old client's `catalog_revision_id` is translated at staging, never at apply; an
  unapproved composition is a validation NO-GO; the number is display-only.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.CompositionFixtures
  alias Cadence.Configuration.OpRow
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels.Compositions
  alias Cadence.SpacecraftTypeStore

  setup do
    org = "org-pins-#{System.unique_integer([:positive])}"
    mid = "mission-pins-#{System.unique_integer([:positive])}"
    {craft, rev1, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    rev2 =
      Fixtures.persist_imported_revision!(org, mid,
        revision_label: "Rev 2",
        yaml: rev2_yaml(),
        approve: false
      )

    %{
      org: org,
      mid: mid,
      scope: scope,
      craft: craft,
      rev1: rev1,
      rev2: rev2,
      comp1: composition!(org, mid, rev1),
      comp2: composition!(org, mid, rev2)
    }
  end

  describe "an old client's catalog_revision_id is translated at staging" do
    test "a create names the catalog revision's one-layer composition in the staged op", c do
      {:ok, staged} = stage(c, [create_profile("Old client", c.rev1.catalog_revision_id)])

      assert %{"document" => %{"composition_id" => composition}} = staged_payload(staged)
      assert composition == c.comp1
    end

    test "an update that changes only the catalog revision also changes the composition", c do
      profile = profile!(c, c.rev1.catalog_revision_id)
      CompositionFixtures.approve!(c.rev2.mission_model_revision_id)

      {:ok, staged} =
        stage(c, [
          update("spacecraft_profile", profile, "catalog_revision_id", c.rev2.catalog_revision_id)
        ])

      changes = staged_payload(staged)["changes"]
      assert %{"value" => composition} = Enum.find(changes, &(&1["path"] == "composition_id"))
      assert composition == c.comp2
    end

    test "a catalog revision and a composition that disagree are refused", c do
      profile = profile!(c, c.rev1.catalog_revision_id)

      rev3 =
        Fixtures.persist_imported_revision!(c.org, c.mid,
          revision_label: "Rev 3",
          yaml: String.replace(rev2_yaml(), "apid: 77", "apid: 78")
        )

      comp3 = composition!(c.org, c.mid, rev3)

      op = %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: profile,
        changes: [
          # Both change, to things that don't match (an unchanged path is dropped at staging).
          %{path: "catalog_revision_id", value: c.rev2.catalog_revision_id},
          %{path: "composition_id", value: comp3}
        ]
      }

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mid, {:ops, [op]})

      assert %{items: [%{errors: errors}]} = Enum.find(checks, &(&1.key == "validation"))

      assert %{message: message, details: %{reason: "mismatch"}} =
               Enum.find(errors, &(&1.path == "composition_id"))

      assert message ==
               "Cadence couldn't match this to catalog rev #{c.rev2.revision_number}; " <>
                 "choose the catalog revision again"
    end
  end

  describe "an unapproved composition is a validation NO-GO at staging" do
    test "a profile pin to a composition with no approved revision", c do
      profile = profile!(c, c.rev1.catalog_revision_id)
      op = update("spacecraft_profile", profile, "composition_id", c.comp2)

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mid, {:ops, [op]})

      assert %{
               items: [%{errors: [%{path: "composition_id", message: message, details: details}]}]
             } =
               Enum.find(checks, &(&1.key == "validation"))

      # mms-ux (a U109 amendment): a one-catalog pin is named by its catalog revision.
      n = c.rev2.revision_number

      assert message ==
               "Catalog rev #{n} isn't approved yet; an org admin approves it in Setup › Catalog first"

      assert %{reason: "not_approved", catalog_revision_number: ^n, composition_id: comp} =
               details

      assert comp == c.comp2
    end

    test "a per-craft pin to a composition with no approved revision", c do
      op =
        update("spacecraft_override", c.craft.spacecraft_id, "composition_id", %{
          "value" => c.comp2,
          "reason" => "Trial"
        })

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mid, {:ops, [op]})

      assert %{items: [%{errors: [%{path: "composition_id"} | _]}]} =
               Enum.find(checks, &(&1.key == "validation"))
    end

    # mms-security's condition 4 (#559), as domain restated it: an old compiler version's approval
    # that this server can't run doesn't count; the pin is refused with re-approval needed.
    test "only an OLD compiler version's revision approved: refused, re-approval needed", c do
      profile = profile!(c, c.rev1.catalog_revision_id)

      ctx = %{
        org: c.org,
        mid: c.mid,
        revision_id: c.rev2.mission_model_revision_id,
        catalog: c.rev2
      }

      old = CompositionFixtures.copy_revision!(ctx, "1")
      CompositionFixtures.link!(ctx, c.comp2, old)
      CompositionFixtures.approve!(old)

      op = update("spacecraft_profile", profile, "composition_id", c.comp2)

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mid, {:ops, [op]})

      assert %{
               items: [%{errors: [%{path: "composition_id", message: message, details: details}]}]
             } =
               Enum.find(checks, &(&1.key == "validation"))

      assert message ==
               "Catalog rev #{c.rev2.revision_number} was approved for an earlier version of " <>
                 "Cadence, so it needs approving again; an org admin does that in Setup › Catalog"

      assert %{reason: "reapproval_needed"} = details
    end

    test "a composition that doesn't exist in the mission", c do
      profile = profile!(c, c.rev1.catalog_revision_id)

      op =
        update("spacecraft_profile", profile, "composition_id", "mission_model_composition:nope")

      assert {:ok, %{verdict: :no_go}} = Configuration.preview(c.scope, c.mid, {:ops, [op]})
    end
  end

  describe "the number is display-only (mms-security on #581)" do
    test "a number given as a write parameter is refused with a field error, never resolved", c do
      profile = profile!(c, c.rev1.catalog_revision_id)

      for op <- [
            update("spacecraft_profile", profile, "composition_id", 1),
            update("spacecraft_profile", profile, "composition_number", 1),
            update("spacecraft_override", c.craft.spacecraft_id, "composition_number", %{
              "value" => 1,
              "reason" => "Trial"
            }),
            update("spacecraft_override", c.craft.spacecraft_id, "composition_id", %{
              "value" => 1,
              "reason" => "Trial"
            })
          ] do
        # A malformed op is refused at its shape check, a field error before any preview.
        assert {:error, {:invalid_op, 0, [%{path: _, message: _} | _]}} =
                 Configuration.preview(c.scope, c.mid, {:ops, [op]}),
               inspect(op)

        assert {:error, {:invalid_op, 0, _}} = stage(c, [op])
      end

      {:ok, stored} = SpacecraftTypeStore.fetch_spacecraft_type(c.org, c.mid, profile)
      assert stored.composition_id == c.comp1
    end
  end

  describe "apply" do
    test "a translated pin applies: the profile stores the composition and its catalog", c do
      profile = profile!(c, c.rev1.catalog_revision_id)

      assert {:ok, %{composition_id: composition, catalog_revision_id: catalog}} =
               SpacecraftTypeStore.fetch_spacecraft_type(c.org, c.mid, profile)

      assert {composition, catalog} == {c.comp1, c.rev1.catalog_revision_id}
    end
  end

  ## Fixtures

  defp composition!(org, mid, catalog) do
    {:ok, %{composition_id: id}} =
      Compositions.for_revision(org, mid, catalog.mission_model_revision_id)

    id
  end

  defp rev2_yaml do
    """
    packets:
      - name: PAYLOAD
        apid: 77
        items:
          - name: power
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """
  end

  defp create_profile(name, catalog) do
    %{
      kind: "spacecraft_profile",
      action: :create,
      entity_id: "profile-pins-#{System.unique_integer([:positive])}",
      document: %{
        "display_name" => name,
        "downlink_protocol" => "tm",
        "uplink_protocol" => "tc",
        "catalog_revision_id" => catalog,
        "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
      }
    }
  end

  defp profile!(c, catalog) do
    %{entity_id: id} = op = create_profile("Pinned", catalog)
    {:ok, staged} = stage(c, [op])
    {:ok, %{state: :applied}} = submit(c, staged)
    id
  end

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}

  defp stage(c, ops), do: Configuration.stage(c.scope, c.mid, %{summary: "Pins"}, ops)

  defp submit(c, staged),
    do:
      Configuration.submit(c.scope, c.mid, staged.change_set_id, %{
        reason: "Composition pins test",
        expected_version: staged.version,
        acknowledged_holds: true
      })

  defp staged_payload(staged) do
    OpRow
    |> where([o], o.change_set_id == ^staged.change_set_id)
    |> select([o], o.payload)
    |> Repo.one!()
  end
end
