defmodule Cadence.MissionModels.SystemSelectionTest do
  @moduledoc """
  ADR-020 P5 (#1078 slice B1): what the systems of a revision hold, which systems an APID
  selection amounts to, and the selection the decom compile makes through it.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Revision, RuntimePlan, SpaceSystem}
  alias Cadence.MissionModels.SystemSelection

  @root SpaceSystem.new(%{qualified_name: "/"})
  @bus SpaceSystem.new(%{qualified_name: "/bus", parent_id: @root.semantic_id})
  @payload SpaceSystem.new(%{qualified_name: "/payload", parent_id: @root.semantic_id})

  defp revision do
    %Revision{
      revision_id: "rev",
      mission_id: "m",
      status: :candidate,
      compiler_version: "v",
      layer_ids: [],
      content_sha256: "sha",
      space_systems: Map.new([@root, @bus, @payload], &{&1.semantic_id, &1})
    }
  end

  defp plan(target, body) do
    %RuntimePlan{
      plan_id: "plan-#{target}",
      target: target,
      target_contract_version: "1",
      mission_model_revision_id: "rev",
      mission_model_content_sha256: "sha",
      layer_ids: [],
      compiler_version: "v",
      status: :ready,
      plan: body,
      content_sha256: "c-#{target}"
    }
  end

  defp packet(system, name, apid, path) do
    %{
      "packet_definition_id" => "pd-" <> name,
      "packet_name" => name,
      "apid" => apid,
      "space_system_id" => system.semantic_id,
      "runtime_name" => path
    }
  end

  defp plans do
    %{
      telemetry:
        plan(:telemetry, %{
          "packet_definitions" => [
            packet(@bus, "HK", 10, "/bus/HK"),
            packet(@bus, "ATT", 11, "/bus/ATT"),
            packet(@payload, "HK", 20, "/payload/HK")
          ]
        }),
      command:
        plan(:command, %{
          "runtime_definitions" => [
            %{
              "command_id" => "c1",
              "name" => "SET_MODE",
              "space_system_id" => @bus.semantic_id,
              "runtime_name" => "/bus/SET_MODE"
            }
          ]
        }),
      algorithm:
        plan(:algorithm, %{"algorithms" => [%{"space_system_id" => @payload.semantic_id}]}),
      monitoring:
        plan(:monitoring, %{
          "policies" => [
            %{"space_system_id" => @bus.semantic_id, "policy_id" => "p1", "scope" => "mission"},
            # The same policy with a per-craft override is one policy.
            %{"space_system_id" => @bus.semantic_id, "policy_id" => "p1", "scope" => "spacecraft"}
          ]
        })
    }
  end

  describe "contributions/2" do
    test "every system with what it owns, by path" do
      assert [root, bus, payload] = SystemSelection.contributions(revision(), plans())
      assert Enum.map([root, bus, payload], & &1.path) == ["/", "/bus", "/payload"]

      assert %{packets: [], commands: [], algorithms: 0, policies: 0, parent_id: nil} = root

      assert [%{name: "ATT", apid: 11}, %{name: "HK", apid: 10, runtime_name: "/bus/HK"}] =
               bus.packets

      assert [%{name: "SET_MODE", runtime_name: "/bus/SET_MODE"}] = bus.commands
      assert bus.policies == 1
      assert bus.parent_id == root.system_id

      assert [%{name: "HK", apid: 20, runtime_name: "/payload/HK"}] = payload.packets
      assert payload.algorithms == 1
    end

    test "a plan that isn't ready contributes nothing" do
      blocked = Map.update!(plans(), :telemetry, &%{&1 | status: :blocked})

      assert [_root, bus, payload] =
               SystemSelection.contributions(revision(), blocked)

      assert bus.packets == [] and payload.packets == []
    end
  end

  describe "effective/3 (an APID selection, as systems)" do
    test "a system with all its containers selected is bound :all" do
      assert [%{path: "/bus", bound: :all, apids: [10, 11]}] =
               SystemSelection.effective(revision(), plans(), {:apids, [10, 11]})
    end

    test "a system with some selected is :some; selected APIDs in no plan name no system" do
      assert [%{path: "/bus", bound: :some, apids: [10]}, %{path: "/payload", bound: :all}] =
               SystemSelection.effective(revision(), plans(), {:apids, [10, 20, 99]})
    end

    test "no APIDs bind no system" do
      assert SystemSelection.effective(revision(), plans(), {:apids, []}) == []
    end
  end

  describe "select/2" do
    test "picks the definitions whose APID is selected" do
      definitions = [%{apid: 10, name: "a"}, %{apid: 11, name: "b"}, %{apid: 20, name: "c"}]

      assert [%{name: "a"}, %{name: "c"}] =
               SystemSelection.select(definitions, {:apids, [20, 10]})

      assert SystemSelection.select(definitions, {:apids, []}) == []
    end
  end
end
