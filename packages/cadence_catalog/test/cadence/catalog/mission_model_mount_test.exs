Code.require_file("../../support/mission_model_mount_fixtures.exs", __DIR__)

defmodule Cadence.Catalog.MissionModelMountTest do
  @moduledoc """
  #444 (ADR-020 Addendum 1, DECISIONS #92): imported layers are mounted under their own subtree
  when they compose, so a second import composes beside the first instead of colliding at the
  root. The mount is a compile input (`mounts: %{layer_id => path}`), never part of the layer, and
  one imported layer at '/' compiles exactly as before.
  """
  use ExUnit.Case, async: true

  import Cadence.Catalog.MissionModelMountFixtures

  alias Cadence.Catalog.MissionModel.{Canonical, Compiler, Declaration, Layer}

  # Compiled on develop 847a3ea4e, before #444: one import alone must stay byte-identical (#108).
  # The revision ids are as then. The plan ids are as #443 defines them (from the plan, not the
  # revision), recomputed once. The monitoring plan's moved again with P3 (#451): contract 2, whose
  # entries carry rule_id/rule_digest/origin/scope. These fixtures declare no policy, so only the
  # contract version changed it.
  @golden %{
    yaml: %{
      revision_id:
        "mission_model_revision:3e6c81e25696e254b3c08306cd3d8f6fdc29aaf23190f37dae2074b148d1fb32",
      content_sha256: "3e6c81e25696e254b3c08306cd3d8f6fdc29aaf23190f37dae2074b148d1fb32",
      plans: %{
        algorithm:
          {"mission_model_plan:36db7e86882d7b9629b3384691853db55ff679a5a09a73edd4043259546d9887",
           "36db7e86882d7b9629b3384691853db55ff679a5a09a73edd4043259546d9887"},
        command:
          {"mission_model_plan:78110393fa3e3bd54ddb4170f15a1d077d176a6d2d0b7f6bb303e6d97b18782f",
           "78110393fa3e3bd54ddb4170f15a1d077d176a6d2d0b7f6bb303e6d97b18782f"},
        monitoring:
          {"mission_model_plan:d1b748660ecccaf933933b1930011890815b669a1a6559644a7dc81ac5d1c79d",
           "d1b748660ecccaf933933b1930011890815b669a1a6559644a7dc81ac5d1c79d"},
        telemetry:
          {"mission_model_plan:0a170285a78a1438a81bc1a157558b8d80f846bef25e4829a9c55aa41feb8dce",
           "0a170285a78a1438a81bc1a157558b8d80f846bef25e4829a9c55aa41feb8dce"}
      }
    },
    xtce: %{
      revision_id:
        "mission_model_revision:d3db142cd502e85ee9df42575d53306617ec4fa6af3bfbb4dc2f9ff9ec28ebc3",
      content_sha256: "d3db142cd502e85ee9df42575d53306617ec4fa6af3bfbb4dc2f9ff9ec28ebc3",
      plans: %{
        algorithm:
          {"mission_model_plan:76170c5fa6497d6796c4bfb0b870b5fdb97974b290eb7c862a632596e7ba808b",
           "76170c5fa6497d6796c4bfb0b870b5fdb97974b290eb7c862a632596e7ba808b"},
        command:
          {"mission_model_plan:370e10394674778a9cc9a02a43a87e1dce88fb78e0465e55e3c45018c3528162",
           "370e10394674778a9cc9a02a43a87e1dce88fb78e0465e55e3c45018c3528162"},
        monitoring:
          {"mission_model_plan:d1b748660ecccaf933933b1930011890815b669a1a6559644a7dc81ac5d1c79d",
           "d1b748660ecccaf933933b1930011890815b669a1a6559644a7dc81ac5d1c79d"},
        telemetry:
          {"mission_model_plan:1ce1ef42fd68603c6cd82e0914409e2a5b07d05619a2539c74a69a8cceaa1cdc",
           "1ce1ef42fd68603c6cd82e0914409e2a5b07d05619a2539c74a69a8cceaa1cdc"}
      }
    }
  }

  describe "one imported layer compiles exactly as before" do
    test "the YAML database's revision and plans keep their identities" do
      assert fingerprints(Compiler.compile([yaml_layer()])) == @golden.yaml
    end

    test "the XTCE document's revision and plans keep their identities" do
      assert fingerprints(Compiler.compile([xtce_layer()])) == @golden.xtce
    end

    test "an empty mounts map, or the layer mounted at '/', changes nothing" do
      layer = yaml_layer()
      plain = fingerprints(Compiler.compile([layer]))

      assert fingerprints(Compiler.compile([layer], mounts: %{})) == plain
      assert fingerprints(Compiler.compile([layer], mounts: %{layer.layer_id => "/"})) == plain
    end

    test "an authored layer over one import still addresses the import's own paths" do
      imported = yaml_layer()
      original = declaration!(imported, :parameter, "/parameters/HK/mode")

      authored =
        Layer.new(%{
          organization_id: "org-alpha",
          mission_id: "mission-alpha",
          layer_kind: :authored,
          name: "operator edit",
          declarations: [
            %{
              kind: :parameter,
              qualified_name: original.qualified_name,
              operation: :extend,
              expected_fingerprint: Declaration.fingerprint(original),
              definition: %{"description" => "edited"}
            }
          ]
        })

      assert {:ok, result} = Compiler.compile([imported, authored])
      assert result.revision.diagnostics == []

      assert result.revision.declarations[original.semantic_id].definition["description"] ==
               "edited"
    end
  end

  describe "two imports, each under its own mount" do
    test "compose side by side, with the compiler owning '/'" do
      bus = yaml_layer()
      payload = xtce_layer()

      assert {:ok, result} =
               Compiler.compile([bus, payload],
                 mounts: %{bus.layer_id => "/bus", payload.layer_id => "/payload"}
               )

      revision = result.revision
      assert blocking(revision) == []
      assert revision.layer_ids == [bus.layer_id, payload.layer_id]

      assert revision.metadata["mounts"] == %{
               bus.layer_id => "/bus",
               payload.layer_id => "/payload"
             }

      systems = revision.space_systems |> Map.values() |> Map.new(&{&1.qualified_name, &1})
      root = Map.fetch!(systems, "/")
      assert root.parent_id == nil
      assert systems["/bus"].parent_id == root.semantic_id
      assert systems["/bus"].name == "bus"
      assert systems["/payload"].parent_id == root.semantic_id
      assert systems["/payload/Vehicle"].parent_id == systems["/payload"].semantic_id

      assert qualified?(revision, :container, "/bus/containers/HK")
      assert qualified?(revision, :parameter, "/bus/parameters/HK/temperature_c")
      assert qualified?(revision, :command, "/bus/commands/SET_MODE")
      assert qualified?(revision, :parameter, "/payload/Vehicle/parameters/temperature")
      assert qualified?(revision, :algorithm, "/payload/Vehicle/algorithms/DoubleTemperature")

      # Every reference resolved inside its own mount, absolute ones included.
      for declaration <- Map.values(revision.declarations), reference <- declaration.references do
        assert is_binary(reference.resolved_id),
               "#{declaration.qualified_name} -> #{reference.source_ref} unresolved"

        mount =
          if String.starts_with?(declaration.qualified_name, "/bus"), do: "/bus", else: "/payload"

        assert String.starts_with?(reference.resolved_qualified_name, mount <> "/")
      end

      # Mounting adds no diagnostic of its own: each plan says what the two layers say alone (the
      # XTCE fixture's container has no APID, so its telemetry is blocked either way).
      {:ok, bus_alone} = Compiler.compile([bus])
      {:ok, payload_alone} = Compiler.compile([payload])

      for target <- Map.keys(result.plans) do
        assert codes(result.plans[target]) ==
                 MapSet.union(codes(bus_alone.plans[target]), codes(payload_alone.plans[target]))
      end
    end

    test "a mounted layer's references keep the source's own text; only resolution moves" do
      bus = yaml_layer()
      payload = xtce_layer("Payload")

      {:ok, result} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/payload"))

      container = qualified!(result.revision, :container, "/bus/containers/HK")
      original = declaration!(bus, :container, "/containers/HK")

      assert Enum.map(container.references, & &1.source_ref) ==
               Enum.map(original.references, & &1.source_ref)

      assert Enum.all?(
               container.references,
               &String.starts_with?(&1.resolved_qualified_name, "/bus/")
             )
    end

    test "an algorithm's outputs name the mounted parameter, so the plan writes the right one" do
      bus = yaml_layer()
      payload = xtce_layer()

      {:ok, result} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/payload"))

      algorithm =
        qualified!(result.revision, :algorithm, "/payload/Vehicle/algorithms/DoubleTemperature")

      parameter =
        qualified!(result.revision, :parameter, "/payload/Vehicle/parameters/double_temperature")

      assert [%{} = output] = algorithm.definition[:outputs] || algorithm.definition["outputs"]
      assert (output[:parameter_id] || output["parameter_id"]) == parameter.semantic_id

      assert (output[:qualified_name] || output["qualified_name"]) ==
               "/payload/Vehicle/parameters/double_temperature"

      refute Enum.any?(result.revision.diagnostics, &(&1.code == "MM_ALGORITHM_OUTPUT_INVALID"))
    end

    test "the layers themselves are unchanged: the mount never enters a layer" do
      bus = yaml_layer()
      payload = xtce_layer()

      {:ok, _result} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/payload"))

      assert yaml_layer().layer_id == bus.layer_id
      assert xtce_layer().layer_id == payload.layer_id
    end

    test "the same layers under other mounts are a different revision" do
      bus = yaml_layer()
      payload = xtce_layer("Payload")

      {:ok, first} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/payload"))

      {:ok, again} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/payload"))

      {:ok, other} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/core", payload, "/payload"))

      assert first.revision.revision_id == again.revision.revision_id
      refute first.revision.revision_id == other.revision.revision_id
    end
  end

  describe "a collision is blocking, never a silent drop" do
    test "two imports at the same mount name both layers and the mount" do
      first = yaml_layer()
      second = yaml_layer("second.yaml")

      {:ok, result} =
        Compiler.compile([first, second],
          mounts: %{first.layer_id => "/bus", second.layer_id => "/bus"}
        )

      assert %{metadata: metadata} = code!(result.revision, "MM_MOUNT_COLLISION")
      assert metadata.mounts == ["/bus", "/bus"]
      assert metadata.layer_ids == [first.layer_id, second.layer_id]

      duplicate = code!(result.revision, "MM_DUPLICATE_IDENTITY")
      assert duplicate.metadata.layer_id == second.layer_id
      assert duplicate.metadata.existing_layer_id == first.layer_id
      assert duplicate.metadata.mount == "/bus"

      assert result.plans.telemetry.status == :blocked
    end

    test "one mount nested under another is refused, in either order (domain, #456)" do
      bus = yaml_layer()
      payload = xtce_layer()

      for {bus_mount, payload_mount} <- [{"/bus", "/bus/payload"}, {"/bus/payload", "/bus"}] do
        {:ok, result} =
          Compiler.compile([bus, payload],
            mounts: mounts(bus, bus_mount, payload, payload_mount)
          )

        assert %{metadata: metadata} = code!(result.revision, "MM_MOUNT_COLLISION")
        assert metadata.layer_ids == [bus.layer_id, payload.layer_id]
        assert metadata.mounts == [bus_mount, payload_mount]
        assert result.plans.telemetry.status == :blocked
      end
    end

    test "sibling mounts that only share a prefix of their names don't collide" do
      bus = yaml_layer()
      payload = xtce_layer()

      {:ok, result} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/bus2"))

      refute Enum.any?(result.revision.diagnostics, &(&1.code == "MM_MOUNT_COLLISION"))
    end

    test "two mounts that lower the same packet, parameter or command name into one target" do
      bus = yaml_layer()
      payload = yaml_layer("payload.yaml")

      {:ok, result} =
        Compiler.compile([bus, payload], mounts: mounts(bus, "/bus", payload, "/payload"))

      collisions =
        Enum.filter(result.revision.diagnostics, &(&1.code == "MM_TARGET_NAME_COLLISION"))

      assert collisions
             |> Enum.map(&{&1.target, &1.metadata.kind, &1.metadata.name})
             |> Enum.sort() ==
               [
                 {:command, :command, "SET_MODE"},
                 {:telemetry, :container, "HK"},
                 {:telemetry, :parameter, "mode"},
                 {:telemetry, :parameter, "temperature_c"}
               ]

      for collision <- collisions do
        assert collision.severity == :error
        assert collision.metadata.mounts == ["/bus", "/payload"]
        assert collision.metadata.layer_ids == [bus.layer_id, payload.layer_id]
      end

      assert result.plans.telemetry.status == :blocked
      assert result.plans.command.status == :blocked
    end

    test "the same short names inside ONE mount are not this check's business" do
      {:ok, result} = Compiler.compile([yaml_layer()], mounts: %{})
      refute Enum.any?(result.revision.diagnostics, &(&1.code == "MM_TARGET_NAME_COLLISION"))
    end
  end

  describe "mounts are checked before compiling" do
    test "only a second or later import at '/' needs a mount (#537: one primary may stay)" do
      bus = yaml_layer()
      payload = xtce_layer()
      third = yaml_layer("third.yaml")

      # Both at '/': the first is the primary, the second needs a mount.
      assert {:error, {:mission_model_mount_required, [id]}} = Compiler.compile([bus, payload])
      assert id == payload.layer_id

      assert {:error, {:mission_model_mount_required, ids}} =
               Compiler.compile([bus, payload, third], mounts: %{payload.layer_id => "/payload"})

      assert ids == [third.layer_id]

      # The primary needn't be the first layer: whichever single import stays at '/'.
      assert {:ok, _result} =
               Compiler.compile([bus, payload],
                 mounts: %{bus.layer_id => "/bus", payload.layer_id => "/"}
               )
    end

    test "the primary at '/' keeps every identity it has alone; the next mounts beside it" do
      bus = yaml_layer()
      payload = xtce_layer()
      {:ok, alone} = Compiler.compile([bus])

      {:ok, result} = Compiler.compile([bus, payload], mounts: %{payload.layer_id => "/payload"})
      revision = result.revision

      # Identities never move silently: every declaration of the primary is where it was.
      for {id, declaration} <- alone.revision.declarations do
        assert %{qualified_name: qualified_name} = Map.fetch!(revision.declarations, id)
        assert qualified_name == declaration.qualified_name
      end

      refute Enum.any?(blocking(revision), &(&1.stage in [:composition, :namespace]))
      root = revision.space_systems |> Map.values() |> Enum.find(&(&1.qualified_name == "/"))
      assert root.semantic_id == Canonical.semantic_id(:space_system, "/")
      assert qualified?(revision, :parameter, "/payload/Vehicle/parameters/temperature")
    end

    test "a mount that reuses one of the primary's top-level names collides (#537)" do
      bus = yaml_layer()
      payload = xtce_layer()

      {:ok, result} =
        Compiler.compile([bus, payload], mounts: %{payload.layer_id => "/containers"})

      assert %{metadata: metadata} = code!(result.revision, "MM_MOUNT_COLLISION")
      assert metadata.layer_ids == [bus.layer_id, payload.layer_id]
      assert metadata.mounts == ["/", "/containers"]
      assert result.plans.telemetry.status == :blocked
    end

    test "a mount must name an imported layer of this compile, at a plain absolute path" do
      bus = yaml_layer()
      payload = xtce_layer()
      both = mounts(bus, "/bus", payload, "/payload")

      authored =
        Layer.new(%{
          organization_id: "org-alpha",
          mission_id: "mission-alpha",
          layer_kind: :authored,
          name: "edit"
        })

      for {mounts, reason} <- [
            {Map.put(both, "mission_model_layer:missing", "/x"), :unknown_layer},
            {Map.put(both, authored.layer_id, "/x"), :authored_layer},
            {%{both | bus.layer_id => "bus"}, :invalid_path},
            {%{both | bus.layer_id => "/bus/../payload"}, :invalid_path},
            {%{both | bus.layer_id => "/bus/"}, :invalid_path},
            {%{both | bus.layer_id => ""}, :invalid_path}
          ] do
        assert {:error, {:mission_model_mount_invalid, _layer_id, ^reason}} =
                 Compiler.compile([bus, payload, authored], mounts: mounts)
      end
    end
  end

  # -- fixtures ----------------------------------------------------------------------------------

  defp mounts(first, first_mount, second, second_mount),
    do: %{first.layer_id => first_mount, second.layer_id => second_mount}

  defp fingerprints({:ok, result}) do
    %{
      revision_id: result.revision.revision_id,
      content_sha256: result.revision.content_sha256,
      plans:
        Map.new(result.plans, fn {target, plan} ->
          {target, {plan.plan_id, plan.content_sha256}}
        end)
    }
  end

  defp codes(plan), do: MapSet.new(plan.diagnostics, & &1.code)

  defp blocking(revision), do: Enum.filter(revision.diagnostics, &(&1.severity == :error))

  defp qualified?(revision, kind, path),
    do: Map.has_key?(revision.declarations, Canonical.semantic_id(kind, path))

  defp qualified!(revision, kind, path),
    do: Map.fetch!(revision.declarations, Canonical.semantic_id(kind, path))

  defp declaration!(%Layer{} = layer, kind, path),
    do:
      Enum.find(layer.declarations, &(&1.kind == kind and &1.qualified_name == path)) ||
        flunk("#{path} missing")

  defp code!(revision, code),
    do:
      Enum.find(revision.diagnostics, &(&1.code == code)) ||
        flunk("no #{code} in #{inspect(Enum.map(revision.diagnostics, & &1.code))}")
end
