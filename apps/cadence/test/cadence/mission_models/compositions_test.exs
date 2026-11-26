defmodule Cadence.MissionModels.CompositionsTest do
  @moduledoc """
  D1 (#541; design §1, §2, §7): mission compositions and their effective revisions.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures

  alias Cadence.MissionModels.{
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

  defp count(schema), do: Repo.aggregate(schema, :count)
end
