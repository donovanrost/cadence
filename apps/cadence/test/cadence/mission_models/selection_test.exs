defmodule Cadence.MissionModels.SelectionTest do
  @moduledoc """
  D3 (#544; design §3): the revision a pinned composition runs is the newest approved, runnable
  one, in a fixed order, and approval never transfers between compiler versions.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.CompositionFixtures
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Compositions, RevisionRow, Selection}
  alias Cadence.Runtime.MissionModelPlanDecoder

  setup do
    org = "org-selection-#{System.unique_integer([:positive])}"
    mid = "mission-selection-#{System.unique_integer([:positive])}"
    {_craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    revision_id = catalog.mission_model_revision_id
    {:ok, composition} = Compositions.for_revision(org, mid, revision_id)

    %{
      org: org,
      mid: mid,
      catalog: catalog,
      revision_id: revision_id,
      composition_id: composition.composition_id
    }
  end

  # A revision of `version`, linked to the fixture's composition after the ones before it.
  defp compile!(c, version) do
    id = CompositionFixtures.copy_revision!(c, version)
    CompositionFixtures.link!(c, c.composition_id, id)
    id
  end

  defp pick(c, opts \\ []), do: Selection.select(c.org, c.mid, c.composition_id, opts)

  test "an approved revision of a runnable version is selected", c do
    CompositionFixtures.approve!(c.revision_id)
    assert {:ok, revision_id} = pick(c)
    assert revision_id == c.revision_id
  end

  test "nothing approved: not_approved", c do
    CompositionFixtures.set_status!([c.revision_id], "candidate")
    assert {:error, :not_approved} = pick(c)
  end

  test "(a) an old runnable approval keeps running while a newer compile waits (domain)", c do
    CompositionFixtures.set_status!([c.revision_id], "candidate")
    old = compile!(c, "1")
    CompositionFixtures.approve!(old)

    # '2' (the fixture's revision) is newer but unapproved: the approved '1' runs.
    assert {:ok, ^old} = pick(c, runnable: ["1", "2"])

    # Once '2' is approved on its own, it runs; '1's approval never carried to it.
    CompositionFixtures.approve!(c.revision_id)
    assert {:ok, revision_id} = pick(c, runnable: ["1", "2"])
    assert revision_id == c.revision_id
  end

  test "(b) only an approval this server can't run: re-approval needed (domain)", c do
    CompositionFixtures.set_status!([c.revision_id], "candidate")
    old = compile!(c, "1")
    CompositionFixtures.approve!(old)

    assert {:error, :reapproval_needed} = pick(c, runnable: ["2"])
  end

  test "a revision outside the runnable list is never selected", c do
    CompositionFixtures.approve!(c.revision_id)
    other = compile!(c, "3")
    CompositionFixtures.approve!(other)

    assert {:ok, revision_id} = pick(c, runnable: ["2"])
    assert revision_id == c.revision_id
  end

  test "newest is the list position, never string order: '10' is newer than '9'", c do
    CompositionFixtures.set_status!([c.revision_id], "candidate")
    nine = compile!(c, "9")
    ten = compile!(c, "10")
    CompositionFixtures.approve!(ten)
    CompositionFixtures.approve!(nine)

    assert {:ok, ^ten} = pick(c, runnable: ["9", "10"])
    # The order is the list's, so reversing it reverses the answer: no hidden string compare.
    assert {:ok, ^nine} = pick(c, runnable: ["10", "9"])
  end

  test "the order is fixed: the same rows always give the same answer", c do
    CompositionFixtures.approve!(c.revision_id)
    a = compile!(c, "2b")
    CompositionFixtures.approve!(a)

    answers = for _ <- 1..5, do: pick(c, runnable: ["2", "2b"])
    assert Enum.uniq(answers) == [{:ok, a}]
  end

  test "ranked/3: every link newest first, with status; select/4 is its first approved runnable",
       c do
    CompositionFixtures.approve!(c.revision_id)
    candidate = compile!(c, "3")
    CompositionFixtures.set_status!([candidate], "candidate")
    old = compile!(c, "1")
    CompositionFixtures.approve!(old)

    runnable = ["1", "2", "3"]
    links = Selection.ranked(c.org, c.mid, c.composition_id, runnable: runnable)

    assert Enum.map(links, &{&1.compiler_version, &1.status}) ==
             [{"3", "candidate"}, {"2", "approved"}, {"1", "approved"}]

    # #577: the newer candidate is the one ahead of the selection in this same order.
    assert {:ok, selected} = pick(c, runnable: runnable)
    assert selected == c.revision_id
    [%{revision_id: ^candidate} | _] = links

    # An unrunnable link sorts after the runnable ones and is marked so.
    assert [%{compiler_version: "1", runnable: false} | _] =
             c.org
             |> Selection.ranked(c.mid, c.composition_id, runnable: ["2", "3"])
             |> Enum.reverse()
  end

  test "every runnable version has a stored revision whose plans this runtime decodes", c do
    for version <- Selection.runnable() do
      assert %RevisionRow{revision_id: id} =
               Repo.get_by(RevisionRow, revision_id: c.revision_id, compiler_version: version),
             "no stored revision of runnable compiler version #{version}: add a fixture for " <>
               "it, or take it off Selection's runnable list"

      assert {:ok, plans} = MissionModels.fetch_runtime_plans(c.org, c.mid, id)
      assert :ok = MissionModelPlanDecoder.validate(plans)
    end
  end
end
