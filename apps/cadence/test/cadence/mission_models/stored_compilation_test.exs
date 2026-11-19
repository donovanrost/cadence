defmodule Cadence.MissionModels.StoredCompilationTest do
  @moduledoc """
  Layer and revision ids are global primary keys stored with ON CONFLICT DO NOTHING (#119). After
  the inserts every row is read back by id AND organization AND mission; a row under another scope
  fails the compilation closed and its decision is never returned (mms-security, ca-security
  11-19). Ids include the organization and mission, so such a row can only come from a collision
  or a bad write; these tests plant one.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.MissionModel.{Compiler, Layer}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{LayerRow, RevisionRow}

  setup do
    org = "org-stored-#{System.unique_integer([:positive])}"
    mid = "mission-stored-#{System.unique_integer([:positive])}"
    other_mid = "mission-stored-other-#{System.unique_integer([:positive])}"
    persist_mission_scope(org, mid)
    persist_mission_scope(org, other_mid)

    layer =
      Layer.new(%{
        organization_id: org,
        mission_id: mid,
        name: "stored",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compiled} = Compiler.compile([layer])
    %{org: org, mid: mid, other_mid: other_mid, layer: layer, revision: compiled.revision}
  end

  test "a first compilation stores a new revision; the same content again matches it", c do
    assert {:ok, _result, %{matched_existing: false, status: "candidate"}} =
             MissionModels.compile_and_store([c.layer])

    assert {:ok, _result, %{matched_existing: true, status: "candidate", revision_id: id}} =
             MissionModels.compile_and_store([c.layer])

    assert id == c.revision.revision_id
  end

  test "a revision row with this id under another mission fails closed", c do
    planted = %{c.revision | mission_id: c.other_mid}
    Repo.insert!(RevisionRow.changeset(planted))

    approved_elsewhere =
      Repo.get!(RevisionRow, c.revision.revision_id)
      |> Ecto.Changeset.change(status: "approved")
      |> Repo.update!()

    assert {:error, :mission_model_scope_mismatch} = MissionModels.compile_and_store([c.layer])
    assert Repo.get!(RevisionRow, c.revision.revision_id) == approved_elsewhere
  end

  test "a layer row with this id under another mission fails closed", c do
    Repo.insert!(LayerRow.changeset(%{c.layer | mission_id: c.other_mid}))

    assert {:error, :mission_model_scope_mismatch} = MissionModels.compile_and_store([c.layer])
    refute Repo.get(RevisionRow, c.revision.revision_id)
  end
end
