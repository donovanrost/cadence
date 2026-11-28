defmodule Cadence.MissionModels.AuthoredLayerTest do
  @moduledoc """
  ADR-020 P3 slice M2 (#451): the next authored layer from a monitoring change set's entries, and
  a composition compiled at a head with its scoped declarations.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Layer}
  alias Cadence.Configuration.{ChangeSetStore, Ledger}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{AuthoredLayer, AuthoredVersionRow, Compositions}

  @org "org-authored-layer"
  @temperature "/parameters/temperature"
  @actor %{"actor_kind" => "user", "user_id" => "composer", "name" => "Composer"}

  setup do
    mission = "mission-authored-layer-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    composition = composition!(mission, "bus", 40)
    %{mission: mission, composition: composition}
  end

  defp composition!(mission, name, max) do
    {:ok, layer} =
      MissionModels.persist_layer(
        Layer.new(%{
          organization_id: @org,
          mission_id: mission,
          name: name,
          declarations: [
            %{kind: :space_system, qualified_name: "/"},
            %{kind: :parameter, qualified_name: @temperature},
            %{
              kind: :monitoring_policy,
              qualified_name: "/monitoring/temperature",
              references: [
                %{expected_kind: :parameter, source_ref: @temperature, role: :parameter}
              ],
              definition: rules(max)
            }
          ]
        })
      )

    {:ok, composition} =
      Compositions.insert_or_get(@org, mission, [{layer.layer_id, "/"}], @actor)

    # Its base, at the current compiler: what a head builds on (and whose command plan it keeps).
    {:ok, _base} = Compositions.effective_revision(@org, mission, composition.composition_id, nil)
    composition.composition_id
  end

  defp rules(max),
    do: %{"default_rules" => [%{"kind" => "range", "upper" => max, "severity" => "warning"}]}

  defp catalog_policy_id,
    do:
      Canonical.semantic_id(
        :monitoring_policy,
        "/monitoring/temperature"
      )

  defp entry(op, id, proposed),
    do: %{kind: "monitoring_policy", op: op, entity_id: id, previous: nil, proposed: proposed}

  defp mission_policy(name, max, extra \\ %{}),
    do:
      Map.merge(
        %{"name" => name, "parameter" => @temperature, "policy_kind" => "limit"},
        Map.merge(rules(max), extra)
      )

  defp next(c, entries),
    do: AuthoredLayer.next(@org, c.mission, entries, [c.composition], "change_set:test")

  test "a mission policy's create becomes a declaration under /mission/monitoring", c do
    doc = mission_policy("Bus temp", 35)

    assert {:ok, %Layer{layer_kind: :authored, version: 1} = layer} =
             next(c, [entry(:create, AuthoredLayer.entity_id("Bus temp"), doc)])

    assert [%Declaration{qualified_name: "/mission/monitoring/Bus_temp", operation: :add}] =
             layer.declarations

    assert layer.metadata == %{"change_set_id" => "change_set:test"}
  end

  test "a catalog policy's update is an explicit replace pinned to the catalog as composed", c do
    {:ok, layer} = next(c, [entry(:update, catalog_policy_id(), mission_policy("ignored", 30))])

    assert [
             %Declaration{operation: :replace, qualified_name: "/monitoring/temperature"} =
               replace
           ] =
             layer.declarations

    assert is_binary(replace.expected_fingerprint)

    # Compiles clean at that layer: the fingerprint is the composed one, so no drift.
    {:ok, result} =
      MissionModels.compose(@org, c.mission, imported_layer_ids(c) ++ [layer.layer_id])

    assert Enum.filter(result.revision.diagnostics, &(&1.severity == :error)) == []
  end

  test "deleting a catalog policy is refused; turning it off is a replace", c do
    assert {:error, {:monitoring_catalog_policy_delete, _}} =
             next(c, [entry(:delete, catalog_policy_id(), nil)])

    assert {:ok, _layer} =
             next(c, [
               entry(
                 :update,
                 catalog_policy_id(),
                 mission_policy("off", 40, %{"disabled" => true})
               )
             ])
  end

  test "a set that changes nothing is refused", c do
    assert {:error, :monitoring_set_changes_nothing} = next(c, [])
  end

  test "a composition compiles at a head with only the declarations scoped to it", c do
    other = composition!(c.mission, "payload", 50)

    scoped = mission_policy("Bus only", 20, %{"compositions" => [c.composition]})

    {:ok, layer} =
      AuthoredLayer.next(
        @org,
        c.mission,
        [entry(:create, AuthoredLayer.entity_id("Bus only"), scoped)],
        [c.composition, other],
        "change_set:scoped"
      )

    record!(c, layer)

    {:ok, here} = Compositions.effective_revision(@org, c.mission, c.composition, layer.layer_id)
    {:ok, there} = Compositions.effective_revision(@org, c.mission, other, layer.layer_id)

    assert policy_paths(c, here) |> Enum.member?("/mission/monitoring/Bus_only")
    refute policy_paths(c, there) |> Enum.member?("/mission/monitoring/Bus_only")

    # Option B (#451): the head runs its base's command plan, the same identity, as its own row.
    {:ok, base} = Compositions.effective_revision(@org, c.mission, c.composition, nil)
    {:ok, head_command} = MissionModels.fetch_plan(@org, c.mission, here, :command)
    {:ok, base_command} = MissionModels.fetch_plan(@org, c.mission, base, :command)

    assert {head_command.plan_id, head_command.content_sha256,
            head_command.target_contract_version} ==
             {base_command.plan_id, base_command.content_sha256,
              base_command.target_contract_version}

    assert head_command.mission_model_revision_id == here
  end

  defp imported_layer_ids(c) do
    {:ok, composition} = Compositions.fetch(@org, c.mission, c.composition)
    Enum.map(composition.imported_layers, & &1.layer_id)
  end

  defp policy_paths(c, revision_id) do
    {:ok, revision} = MissionModels.fetch_revision(@org, c.mission, revision_id)

    for {_id, %{kind: :monitoring_policy, qualified_name: path}} <- revision.declarations,
        do: path
  end

  # A version for the layer as an applied set would record it (the record rule is AuthoredHeadTest's).
  defp record!(c, layer) do
    Repo.insert!(%AuthoredVersionRow{
      organization_id: @org,
      mission_id: c.mission,
      version: layer.version,
      layer_id: layer.layer_id,
      change_set_id: change_set!(c).change_set_id,
      revision_number: 1,
      approval: "direct",
      decided_at: DateTime.utc_now()
    })

    Repo.query!("SET CONSTRAINTS ALL DEFERRED")
  end

  defp change_set!(c) do
    Ledger.ensure_head(@org, c.mission)

    {:ok, set} =
      Repo.transaction(fn ->
        ChangeSetStore.lock_or_open(
          @org,
          c.mission,
          1,
          %{"kind" => "user", "id" => "u"},
          "monitoring"
        )
      end)

    set
  end
end
