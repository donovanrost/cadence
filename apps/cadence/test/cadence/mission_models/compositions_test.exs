defmodule Cadence.MissionModels.CompositionsTest do
  @moduledoc """
  D1 (#541; design §1, §2, §7): mission compositions and their effective revisions.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.MissionModel.Compiler
  alias Cadence.MissionModels

  alias Cadence.MissionModels.{
    CompositionBackfill,
    CompositionRow,
    Compositions,
    EffectiveRevisionRow
  }

  @actor %{"actor_kind" => "user", "user_id" => "composer-a", "name" => "Composer A"}

  setup do
    org = "org-compositions-#{System.unique_integer([:positive])}"
    mid = "mission-compositions-#{System.unique_integer([:positive])}"
    {_craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    %{org: org, mid: mid, catalog: revision, revision_id: revision.mission_model_revision_id}
  end

  describe "identity (#108)" do
    test "the id is pinned: the canonical term {org, mission, layers sorted by mount}" do
      assert Compositions.id("org", "mission", [{"layer-b", "/payload"}, {"layer-a", "/"}]) ==
               "mission_model_composition:c02384f13cbaa1e40999a6990bdad98b357c9f11dc7b9269b4d4946b6799d00c"

      # Order-free: the same layers in another order are the same composition.
      assert Compositions.id("org", "mission", [{"layer-a", "/"}, {"layer-b", "/payload"}]) ==
               Compositions.id("org", "mission", [{"layer-b", "/payload"}, {"layer-a", "/"}])

      refute Compositions.id("org", "other", [{"layer-a", "/"}]) ==
               Compositions.id("org", "mission", [{"layer-a", "/"}])
    end
  end

  describe "an import creates its own one-layer composition (§1)" do
    test "at '/', with the importer as creator, linked to the revision it compiled", c do
      assert {:ok, composition} = Compositions.for_revision(c.org, c.mid, c.revision_id)

      assert [%{layer_id: layer_id, mount: "/", content_sha256: sha}] =
               composition.imported_layers

      assert is_binary(sha) and is_binary(layer_id)
      assert composition.composition_id == Compositions.id(c.org, c.mid, [{layer_id, "/"}])
      assert composition.created_by["actor_kind"] in ["user", "service", "system"]

      assert {:ok, revision_id} =
               Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

      assert revision_id == c.revision_id
    end

    test "insert-or-get: identical content returns the first row and its first creator", c do
      {:ok, composition} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      [%{layer_id: layer_id}] = composition.imported_layers

      assert {:ok, again} = Compositions.insert_or_get(c.org, c.mid, [{layer_id, "/"}], @actor)
      assert again.composition_id == composition.composition_id
      assert again.created_by == composition.created_by
    end

    test "the creator is stored as kind and ids only, never a stored name (#146)", c do
      {:ok, first} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      [%{layer_id: a}] = first.imported_layers
      b = second_layer!(c)

      {:ok, composition} =
        Compositions.insert_or_get(c.org, c.mid, [{a, "/"}, {b, "/payload"}], @actor)

      assert composition.created_by == %{"actor_kind" => "user", "user_id" => "composer-a"}
      refute Map.has_key?(first.created_by, "name")
    end

    test "a system actor keeps its run_by, the person #513 counts, and drops its name", c do
      {:ok, first} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      [%{layer_id: a}] = first.imported_layers
      b = second_layer!(c)

      seed = %{
        "actor_kind" => "system",
        "system_id" => "seed:compositions",
        "run_by" => "user-runner",
        "name" => "Seed (test)"
      }

      {:ok, composition} = Compositions.insert_or_get(c.org, c.mid, [{a, "/"}, {b, "/p"}], seed)

      assert composition.created_by == %{
               "actor_kind" => "system",
               "system_id" => "seed:compositions",
               "run_by" => "user-runner"
             }
    end
  end

  describe "a bad composition is refused at the write, and nothing is written" do
    test "unknown or foreign layers, authored layers, bad grammar, bounds, collisions", c do
      {:ok, composition} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      [%{layer_id: a}] = composition.imported_layers
      b = second_layer!(c)
      before = count(CompositionRow)

      for layers <- [
            [],
            [{"mission_model_layer:missing", "/"}],
            [{a, "/"}, {a, "/x"}],
            [{a, "bus"}],
            [{a, "/a/../b"}],
            [{a, "/has space"}],
            [{a, "/a/b/c/d/e"}],
            [{a, "/"}, {b, "/"}],
            [{a, "/bus"}, {b, "/bus/sub"}],
            [{a, "/bus"}, {b, "/bus"}]
          ] do
        assert {:error, {:mission_model_composition_invalid, _reason}} =
                 Compositions.insert_or_get(c.org, c.mid, layers, @actor),
               inspect(layers)
      end

      # Another tenant can't name these layers.
      assert {:error, {:mission_model_composition_invalid, {:unknown_layer, ^a}}} =
               Compositions.insert_or_get("org-other", c.mid, [{a, "/"}], @actor)

      assert count(CompositionRow) == before
    end
  end

  describe "effective revisions (§2)" do
    test "two imports compose once; the next call returns the same link", c do
      {:ok, first} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      [%{layer_id: a}] = first.imported_layers
      b = second_layer!(c)

      {:ok, composition} =
        Compositions.insert_or_get(c.org, c.mid, [{a, "/"}, {b, "/payload"}], @actor)

      assert [%{mount: "/"}, %{mount: "/payload"}] = composition.imported_layers

      assert {:ok, revision_id} =
               Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

      revisions = count(Cadence.MissionModels.RevisionRow)

      assert {:ok, ^revision_id} =
               Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)

      assert count(Cadence.MissionModels.RevisionRow) == revisions
      assert {:ok, %{composition_id: id}} = Compositions.for_revision(c.org, c.mid, revision_id)
      assert id == composition.composition_id
      refute revision_id == c.revision_id
    end

    test "concurrent calls compile once and link once (advisory lock)", c do
      {:ok, first} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      [%{layer_id: a}] = first.imported_layers
      b = second_layer!(c)
      {:ok, composition} = Compositions.insert_or_get(c.org, c.mid, [{a, "/"}, {b, "/p"}], @actor)

      results =
        1..3
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Compositions.effective_revision(c.org, c.mid, composition.composition_id, nil)
          end)
        end)
        |> Enum.map(&Task.await(&1, 30_000))

      assert [{:ok, id}, {:ok, id}, {:ok, id}] = results

      assert Repo.aggregate(
               where(EffectiveRevisionRow, composition_id: ^composition.composition_id),
               :count
             ) == 1
    end

    test "authored heads wait for phase 3", c do
      {:ok, composition} = Compositions.for_revision(c.org, c.mid, c.revision_id)

      assert {:error, :authored_layers_not_supported} =
               Compositions.effective_revision(c.org, c.mid, composition.composition_id, "head-1")
    end
  end

  describe "immutability (#116's pattern)" do
    test "no UPDATE, DELETE or TRUNCATE on any of the three tables", c do
      {:ok, _} = Compositions.for_revision(c.org, c.mid, c.revision_id)

      for table <- ~w(mission_model_compositions mission_model_composition_layers
                      mission_model_effective_revisions) do
        for sql <- [
              "UPDATE #{table} SET mission_id = mission_id",
              "DELETE FROM #{table}",
              "TRUNCATE #{table} CASCADE"
            ] do
          assert_raise Postgrex.Error, ~r/immutable/, fn -> Repo.query!(sql) end
        end
      end
    end
  end

  describe "the one-to-one migration (§7)" do
    test "every catalog revision's model revision gets its one-layer composition and link", c do
      lift_and_clear!()
      assert {:error, :not_found} = Compositions.for_revision(c.org, c.mid, c.revision_id)

      assert %{composed: composed, linked: linked} = CompositionBackfill.run(Repo)
      assert composed >= 1 and linked >= 1

      assert {:ok, composition} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      assert [%{mount: "/"}] = composition.imported_layers

      assert composition.created_by == %{
               "actor_kind" => "system",
               "system_id" => "migration:20261120060000"
             }

      # Idempotent (a re-run links nothing new), and the approval columns are untouched.
      {:ok, before} = MissionModels.fetch_revision(c.org, c.mid, c.revision_id)
      assert %{linked: 0} = CompositionBackfill.run(Repo)
      assert {:ok, ^before} = MissionModels.fetch_revision(c.org, c.mid, c.revision_id)
    end

    test "two compiler versions of one layer: each its own link, each approved on its own", c do
      old = copy_revision!(c, "1")
      lift_and_clear!()

      CompositionBackfill.run(Repo)

      assert {:ok, %{composition_id: id}} = Compositions.for_revision(c.org, c.mid, c.revision_id)
      assert {:ok, %{composition_id: ^id}} = Compositions.for_revision(c.org, c.mid, old)

      assert ["1", Compiler.compiler_version()] ==
               Repo.all(
                 from(e in EffectiveRevisionRow,
                   where: e.composition_id == ^id,
                   order_by: e.compiler_version,
                   select: e.compiler_version
                 )
               )

      # Approving the old version's revision doesn't carry forward: the effective revision stays
      # the current version's, and its own status is untouched.
      set_status!([c.revision_id, old], "candidate")
      approve!(old)
      {:ok, current} = MissionModels.fetch_revision(c.org, c.mid, c.revision_id)
      refute current.status in [:approved, "approved"]
      assert {:ok, revision_id} = Compositions.effective_revision(c.org, c.mid, id, nil)
      assert revision_id == c.revision_id
    end

    test "a collision at one composition and compiler version raises; nothing is chosen", c do
      _same_version = copy_revision!(c, Compiler.compiler_version())
      lift_and_clear!()

      assert_raise RuntimeError, ~r/refusing to choose one/, fn ->
        CompositionBackfill.run(Repo)
      end
    end

    test "an approved revision with a blocking diagnostic raises", c do
      lift_and_clear!()
      approve!(c.revision_id)

      Repo.query!(
        """
        INSERT INTO mission_model_diagnostics
          (diagnostic_id, revision_id, organization_id, mission_id, code, severity, stage,
           inserted_at)
        VALUES ($1, $2, $3, $4, 'MM_TEST_BLOCKING', 'error', 'compile', now())
        """,
        ["diag-#{System.unique_integer([:positive])}", c.revision_id, c.org, c.mid]
      )

      assert_raise RuntimeError, ~r/blocking_diagnostics/, fn -> CompositionBackfill.run(Repo) end
    end

    test "guard!: an approved, catalog-named revision with no link raises, naming it", c do
      lift_and_clear!()
      approve!(c.revision_id)

      assert_raise RuntimeError, ~r/#{Regex.escape(c.revision_id)}/, fn ->
        CompositionBackfill.guard!(Repo)
      end
    end

    test "guard: every approved revision ends with a composition naming it", c do
      lift_and_clear!()

      approve!(c.revision_id)
      CompositionBackfill.run(Repo)

      for [revision_id, org, mission] <-
            Repo.query!(
              "SELECT r.revision_id, r.organization_id, r.mission_id FROM mission_model_revisions r " <>
                "JOIN catalog_revisions cr ON cr.mission_model_revision_id = r.revision_id " <>
                "WHERE r.status = 'approved'"
            ).rows do
        assert {:ok, _} = Compositions.for_revision(org, mission, revision_id)
      end
    end
  end

  ## Fixtures

  # A second imported layer in the mission: another catalog with a different packet name.
  defp second_layer!(c) do
    yaml = """
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

    revision =
      Fixtures.persist_imported_revision!(c.org, c.mid, revision_label: "Payload", yaml: yaml)

    {:ok, composition} =
      Compositions.for_revision(c.org, c.mid, revision.mission_model_revision_id)

    [%{layer_id: layer_id}] = composition.imported_layers
    layer_id
  end

  # The rows imports wrote, cleared in this sandbox so the backfill runs as on an old database.
  defp lift_and_clear! do
    for table <- ~w(mission_model_effective_revisions mission_model_composition_layers
                    mission_model_compositions) do
      Repo.query!("ALTER TABLE #{table} DISABLE TRIGGER USER")
      Repo.query!("DELETE FROM #{table}")
      Repo.query!("ALTER TABLE #{table} ENABLE TRIGGER USER")
    end
  end

  defp count(schema), do: Repo.aggregate(schema, :count)

  defp approve!(revision_id), do: set_status!([revision_id], "approved")

  defp set_status!(revision_ids, status),
    do:
      Repo.query!(
        "UPDATE mission_model_revisions SET status = $2 WHERE revision_id = ANY($1)",
        [revision_ids, status]
      )

  # A copy of the fixture's revision under another id and compiler version, with its layers and a
  # catalog revision naming it: as if an older (or a rival) compiler had made it.
  defp copy_revision!(c, version) do
    new_id = "mission_model_revision:copy-#{System.unique_integer([:positive])}"

    copy = fn table, key, changes ->
      Repo.query!(
        "INSERT INTO #{table} SELECT (jsonb_populate_record(NULL::#{table}, " <>
          "to_jsonb(t) || $2::jsonb)).* FROM #{table} t WHERE t.#{key} = $1",
        [c.revision_id, changes]
      )
    end

    copy.("mission_model_revisions", "revision_id", %{
      "revision_id" => new_id,
      "compiler_version" => version,
      "content_sha256" => Base.encode16(:crypto.hash(:sha256, new_id), case: :lower)
    })

    copy.("mission_model_revision_layers", "revision_id", %{"revision_id" => new_id})

    run_id = "catalog_import_run:copy-#{new_id}"

    Repo.query!(
      "INSERT INTO catalog_import_runs SELECT (jsonb_populate_record(NULL::catalog_import_runs, " <>
        "to_jsonb(t) || jsonb_build_object('import_run_id', $2::text))).* " <>
        "FROM catalog_import_runs t WHERE t.import_run_id = $1",
      [c.catalog.import_run_id, run_id]
    )

    Repo.query!(
      "INSERT INTO catalog_revisions SELECT (jsonb_populate_record(NULL::catalog_revisions, " <>
        "to_jsonb(t) || jsonb_build_object('catalog_revision_id', $2::text, " <>
        "'mission_model_revision_id', $3::text, 'revision_number', t.revision_number + 1000, " <>
        "'revision_label', t.revision_label || ' (copy)', 'import_run_id', $4::text))).* " <>
        "FROM catalog_revisions t WHERE t.catalog_revision_id = $1",
      [c.catalog.catalog_revision_id, "catalog_revision:copy-#{new_id}", new_id, run_id]
    )

    new_id
  end
end
