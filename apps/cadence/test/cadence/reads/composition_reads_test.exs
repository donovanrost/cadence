defmodule Cadence.Reads.CompositionReadsTest do
  @moduledoc """
  D2 (#543; design `mission-composition-design.md` §6): the composition the reads show beside a
  revision's catalog revision. The per-mission number (mms-engineer's note 1), the layer's
  earliest catalog revision (domain's rule (b)), `created_by` and the importers named by #146
  (with #513's `run_by`), and the approval read's `importers`, `breaking_base` and `composer`.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog
  alias Cadence.Catalog.Actor
  alias Cadence.Control.ModelApprovalGate

  alias Cadence.MissionModels.{
    CompositionNumberRow,
    CompositionRow,
    Compositions,
    CompositionViews
  }

  alias Cadence.Reads.{CompositionActors, MissionModelApprovals}
  alias Cadence.Reads.MissionModelApprovals.CompositionKeys

  @migration %{"actor_kind" => "system", "system_id" => "migration:20261120060000"}

  setup do
    org = "org-d2-#{System.unique_integer([:positive])}"
    mid = "mission-d2-#{System.unique_integer([:positive])}"
    {_craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    %{org: org, mid: mid, catalog: catalog, revision_id: catalog.mission_model_revision_id}
  end

  describe "the per-mission number (mms-engineer's note 1)" do
    test "a mission's compositions are numbered 1, 2, … in order of creation; identical content keeps its number",
         c do
      a = layer_of(c, c.revision_id)

      b =
        c
        |> import!("Payload", payload_yaml())
        |> then(&layer_of(c, &1.mission_model_revision_id))

      assert number(c, c.revision_id) == 1

      {:ok, two} =
        Compositions.insert_or_get(c.org, c.mid, [{a, "/"}, {b, "/payload"}], @migration)

      assert numbers(c) |> Map.fetch!(two.composition_id) == 3

      {:ok, again} =
        Compositions.insert_or_get(c.org, c.mid, [{b, "/payload"}, {a, "/"}], @migration)

      assert again.composition_id == two.composition_id
      assert numbers(c) |> Map.values() |> Enum.sort() == [1, 2, 3]
    end

    test "a number can't be changed or deleted (immutable, like D1's rows)", c do
      composition_id = composition_id(c, c.revision_id)

      assert_raise Postgrex.Error, ~r/immutable/, fn ->
        Repo.query!(
          "UPDATE mission_model_composition_numbers SET number = 99 WHERE composition_id = $1",
          [composition_id]
        )
      end

      assert_raise Postgrex.Error, ~r/immutable/, fn ->
        Repo.query!("DELETE FROM mission_model_composition_numbers WHERE composition_id = $1", [
          composition_id
        ])
      end
    end

    test "guard: every composition has a number" do
      unnumbered =
        from(composition in CompositionRow,
          left_join: number in CompositionNumberRow,
          on:
            number.organization_id == composition.organization_id and
              number.mission_id == composition.mission_id and
              number.composition_id == composition.composition_id,
          where: is_nil(number.number),
          select: composition.composition_id
        )
        |> Repo.all()

      assert unnumbered == []
    end
  end

  describe "the shared composition object" do
    test "one layer at '/', named by the earliest catalog revision that imported it (rule (b))",
         c do
      # A re-import of the same file: a second catalog revision. If it carries the same layer
      # (#119), the layer still names the first catalog revision; otherwise its own.
      later = import!(c, "Again", nil)
      same_layer? = layer_of(c, later.mission_model_revision_id) == layer_of(c, c.revision_id)

      assert %{imported_layers: [%{catalog_revision: %{id: later_names}}]} =
               for_revision(c, later.mission_model_revision_id)

      assert later_names ==
               if(same_layer?, do: c.catalog.catalog_revision_id, else: later.catalog_revision_id)

      composition = c |> for_revision(c.revision_id)

      assert %{
               composition_id: "mission_model_composition:" <> _,
               number: 1,
               imported_layers: [%{mount: "/", catalog_revision: catalog_revision}],
               created_at: %DateTime{}
             } = composition

      assert catalog_revision.id == c.catalog.catalog_revision_id
      assert catalog_revision.number == c.catalog.revision_number
      assert %{id: database_id, name: "Bus " <> _} = catalog_revision.database
      assert database_id == c.catalog.catalog_database_id
    end

    test "created_by: a seed names its runner while a member; the migration's actor is null", c do
      person = member!(c, "Mira K.")
      seed = Actor.system("seed:demo", "Seed", person.user_id)
      revision = import!(c, "Seeded", payload_yaml(), seed)

      assert %{created_by: by} = for_revision(c, revision.mission_model_revision_id)

      assert by == %{
               kind: "system",
               id: "seed:demo",
               name: nil,
               run_by: %{id: person.user_id, name: "Mira K."}
             }

      # The fixture's own runner isn't a person: run_by reads unnamed, never echoed.
      assert %{created_by: %{run_by: %{id: nil, name: nil}}} = for_revision(c, c.revision_id)

      a = layer_of(c, c.revision_id)

      {:ok, migrated} =
        Compositions.insert_or_get(
          c.org,
          c.mid,
          [{a, "/"}, {layer_of(c, revision.mission_model_revision_id), "/p"}],
          @migration
        )

      view = CompositionViews.fetch(c.org, c.mid, migrated.composition_id)
      names = CompositionActors.names(c.org, [view.created_by])
      assert CompositionActors.named(view, names).created_by == nil
    end

    test "a person who isn't a member is neither named nor identified; never an email", c do
      outsider = user!("Pat Elsewhere")

      revision =
        import!(c, "Outsider", payload_yaml(), Actor.system("seed:x", "Seed", outsider.user_id))

      assert %{created_by: %{run_by: %{id: nil, name: nil}}} =
               for_revision(c, revision.mission_model_revision_id)

      refute inspect(for_revision(c, revision.mission_model_revision_id)) =~ "@"
    end

    test "a revision no composition names has none", c do
      assert CompositionActors.for_revisions(c.org, c.mid, ["mission_model_revision:none", nil]) ==
               %{}
    end
  end

  describe "importer documents (mms-engineer's parity note on #581)" do
    test "model_import_documents/3 counts exactly the actors model_import_actors/3 does", c do
      person = member!(c, "Ida")
      service_id = "service_identity:d2-#{System.unique_integer([:positive])}"

      actors = [
        %{"actor_kind" => "user", "user_id" => person.user_id, "name" => "Ida"},
        %{"actor_kind" => "service", "service_identity_id" => service_id, "name" => "Bot"},
        Actor.system("seed:parity", "Seed", person.user_id)
      ]

      for {actor, n} <- Enum.with_index(actors) do
        yaml = String.replace(payload_yaml(), "apid: 77", "apid: #{80 + n}")
        id = import!(c, "Parity #{n}", yaml, actor).mission_model_revision_id

        documents = Catalog.model_import_documents(c.org, c.mid, id)
        counted = Catalog.model_import_actors(c.org, c.mid, id)

        assert documents |> Enum.map(&Catalog.model_import_actor_of/1) |> Enum.sort() ==
                 Enum.sort(counted)

        assert counted != []
      end
    end
  end

  describe "the approval read's keys (E)" do
    test "importers per layer, and breaking_base is exactly what approval compares against", c do
      person = member!(c, "Ada")

      revision =
        import!(c, "Second", payload_yaml(), Actor.system("seed:y", "Seed", person.user_id))

      id = revision.mission_model_revision_id

      keys = CompositionKeys.read(c.org, c.mid, id)
      assert keys.composition.composition_id == composition_id(c, id)

      assert [%{layer_id: layer_id, importers: importers, importers_count: count}] =
               keys.importers

      assert count == length(importers) and count <= 100
      assert layer_id == layer_of(c, id)
      assert %{kind: "system", run_by: %{id: person_id, name: "Ada"}} = hd(importers)
      assert person_id == person.user_id

      base = ModelApprovalGate.default_baseline(c.org, c.mid, id)

      case keys.breaking_base do
        nil ->
          assert base == nil

        breaking_base ->
          assert breaking_base.revision_id == base

          assert breaking_base.composition ==
                   Map.take(for_revision(c, base), [:composition_id, :number])
      end
    end

    test "composer: refused only for having composed it, not for importing a layer", c do
      composer = member!(c, "Composer")
      a = layer_of(c, c.revision_id)

      b =
        c
        |> import!("Payload", payload_yaml())
        |> then(&layer_of(c, &1.mission_model_revision_id))

      actor = %{"actor_kind" => "user", "user_id" => composer.user_id}

      {:ok, composition} =
        Compositions.insert_or_get(c.org, c.mid, [{a, "/"}, {b, "/payload"}], actor)

      {:ok, revision_id} =
        Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

      assert CompositionKeys.composer?(c.org, c.mid, revision_id, composer.user_id)

      # fe-setup on #581: a composed revision has no catalog revision of its own, but E1's check
      # approves it (every layer catalog-named), so the read doesn't flag it not_in_catalog.
      scope = Fixtures.user_scope(c.org, "viewer")
      assert {:ok, read} = MissionModelApprovals.read(scope, c.mid, revision_id)
      assert read.catalog_revision == nil
      assert read.cannot_approve_because == nil
      # The layers' runner imported them: refused as an importer, so not "composer".
      refute CompositionKeys.composer?(c.org, c.mid, revision_id, "test-fixture-runner")
      refute CompositionKeys.composer?(c.org, c.mid, revision_id, nil)
    end
  end

  defp import!(c, label, yaml, requested_by \\ nil) do
    opts = [revision_label: label, catalog_database_id: c.catalog.catalog_database_id]
    opts = if yaml, do: Keyword.put(opts, :yaml, yaml), else: opts
    opts = if requested_by, do: Keyword.put(opts, :requested_by, requested_by), else: opts
    Fixtures.persist_imported_revision!(c.org, c.mid, opts)
  end

  defp for_revision(c, revision_id),
    do: c.org |> CompositionActors.for_revisions(c.mid, [revision_id]) |> Map.fetch!(revision_id)

  defp composition_id(c, revision_id) do
    {:ok, composition} = Compositions.for_revision(c.org, c.mid, revision_id)
    composition.composition_id
  end

  defp layer_of(c, revision_id) do
    {:ok, %{imported_layers: [%{layer_id: layer_id}]}} =
      Compositions.for_revision(c.org, c.mid, revision_id)

    layer_id
  end

  defp number(c, revision_id), do: c |> numbers() |> Map.fetch!(composition_id(c, revision_id))

  defp numbers(c) do
    from(n in CompositionNumberRow,
      where: n.organization_id == ^c.org and n.mission_id == ^c.mid,
      select: {n.composition_id, n.number}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp user!(name) do
    id = "user-d2-#{System.unique_integer([:positive])}"
    user = User.new(%{user_id: id, email: id <> "@example.test", display_name: name})
    Repo.insert!(UserRow.changeset(user))
    user
  end

  defp member!(c, name) do
    user = user!(name)

    OrganizationMembership.new(%{user_id: user.user_id, organization_id: c.org, role: :member})
    |> OrganizationMembershipRow.changeset()
    |> Repo.insert!()

    user
  end

  defp payload_yaml do
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
end
