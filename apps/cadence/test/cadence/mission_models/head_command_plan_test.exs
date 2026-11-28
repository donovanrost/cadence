defmodule Cadence.MissionModels.HeadCommandPlanTest do
  @moduledoc """
  Option B (#451, agreed with commanding): a revision at an authored head runs its base's command
  plan unchanged. Checked with commanding's exact-authoring model, whose commands have encoding
  steps (atom values in memory, strings as stored): the fresh plan and the stored base plan are
  compared in the stored form (commanding-eng's report on #1106).
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.CommandReviewFixtures
  alias Cadence.Configuration.{ChangeSetStore, Ledger}
  alias Cadence.ExactCommandAuthoringFixtures
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{AuthoredVersionRow, Compositions, RevisionRow}

  @actor %{"actor_kind" => "user", "user_id" => "composer", "name" => "Composer"}

  test "a head over commanding's model keeps the base's command plan identity" do
    c = CommandReviewFixtures.scope!()
    ExactCommandAuthoringFixtures.activate!(c.org, c.mission)

    revision_id =
      Repo.one!(
        from(r in RevisionRow, where: r.mission_id == ^c.mission, select: r.revision_id, limit: 1)
      )

    {:ok, revision} = MissionModels.fetch_revision(c.org, c.mission, revision_id)
    [layer_id] = revision.layer_ids

    {:ok, composition} = Compositions.insert_or_get(c.org, c.mission, [{layer_id, "/"}], @actor)

    {:ok, base} =
      Compositions.effective_revision(c.org, c.mission, composition.composition_id, nil)

    {:ok, authored} =
      MissionModels.persist_layer(
        Layer.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          layer_kind: :authored,
          name: "monitoring",
          declarations: [%{kind: :parameter, qualified_name: "/authored/x"}]
        })
      )

    record!(c, authored)

    assert {:ok, head} =
             Compositions.effective_revision(
               c.org,
               c.mission,
               composition.composition_id,
               authored.layer_id
             )

    {:ok, head_command} = MissionModels.fetch_plan(c.org, c.mission, head, :command)
    {:ok, base_command} = MissionModels.fetch_plan(c.org, c.mission, base, :command)

    assert head_command.plan["runtime_definitions"] != []

    assert {head_command.plan_id, head_command.content_sha256,
            head_command.target_contract_version} ==
             {base_command.plan_id, base_command.content_sha256,
              base_command.target_contract_version}
  end

  # A recorded version, as an applied monitoring set would leave it (the rule is AuthoredHeadTest's).
  defp record!(c, layer) do
    Ledger.ensure_head(c.org, c.mission)

    {:ok, set} =
      Repo.transaction(fn ->
        ChangeSetStore.lock_or_open(
          c.org,
          c.mission,
          1,
          %{"kind" => "user", "id" => "u"},
          "monitoring"
        )
      end)

    Repo.insert!(%AuthoredVersionRow{
      organization_id: c.org,
      mission_id: c.mission,
      version: 1,
      layer_id: layer.layer_id,
      change_set_id: set.change_set_id,
      revision_number: 1,
      approval: "direct",
      decided_at: DateTime.utc_now()
    })
  end
end
