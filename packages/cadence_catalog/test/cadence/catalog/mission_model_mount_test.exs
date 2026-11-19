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
  @golden %{
    yaml: %{
      revision_id:
        "mission_model_revision:3e6c81e25696e254b3c08306cd3d8f6fdc29aaf23190f37dae2074b148d1fb32",
      content_sha256: "3e6c81e25696e254b3c08306cd3d8f6fdc29aaf23190f37dae2074b148d1fb32",
      plans: %{
        algorithm:
          {"mission_model_plan:1822dd9dc18175e126ae0d5e4edf5327e2992508d30335280ced522a6a4aaba0",
           "1822dd9dc18175e126ae0d5e4edf5327e2992508d30335280ced522a6a4aaba0"},
        command:
          {"mission_model_plan:b2ab7e97449dc1f24e21fe4f2dfb62f71b3f6c0b7d31c59ca38b38da72307b5a",
           "b2ab7e97449dc1f24e21fe4f2dfb62f71b3f6c0b7d31c59ca38b38da72307b5a"},
        monitoring:
          {"mission_model_plan:f7af4eb8537688244bcf0108aabd524ae7f70119181cb6550fec50d9222de550",
           "f7af4eb8537688244bcf0108aabd524ae7f70119181cb6550fec50d9222de550"},
        telemetry:
          {"mission_model_plan:beec39ad170a1c15738a54b8b30b3a3ce4bf65cfda2acb2e6964970540478e57",
           "beec39ad170a1c15738a54b8b30b3a3ce4bf65cfda2acb2e6964970540478e57"}
      }
    },
    xtce: %{
      revision_id:
        "mission_model_revision:d3db142cd502e85ee9df42575d53306617ec4fa6af3bfbb4dc2f9ff9ec28ebc3",
      content_sha256: "d3db142cd502e85ee9df42575d53306617ec4fa6af3bfbb4dc2f9ff9ec28ebc3",
      plans: %{
        algorithm:
          {"mission_model_plan:63102f64e2245fc7a315a5c54886a5708d280325181c636a2cca0e1ab7dbb22d",
           "63102f64e2245fc7a315a5c54886a5708d280325181c636a2cca0e1ab7dbb22d"},
        command:
          {"mission_model_plan:496e3f4bf421a30078636e94d03f7adf011465d898fe971905ed67fa9c73ed58",
           "496e3f4bf421a30078636e94d03f7adf011465d898fe971905ed67fa9c73ed58"},
        monitoring:
          {"mission_model_plan:1300e92919e9371ab97cc9de034665abdcb86f24fbcc561221efaa919abe3392",
           "1300e92919e9371ab97cc9de034665abdcb86f24fbcc561221efaa919abe3392"},
        telemetry:
          {"mission_model_plan:df41268a64fab4a39630b4f87b8aa47a12f79fa261e1d2ea9faa1a068e403049",
           "df41268a64fab4a39630b4f87b8aa47a12f79fa261e1d2ea9faa1a068e403049"}
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
    test "two imports need a mount each: the compiler owns '/'" do
      bus = yaml_layer()
      payload = xtce_layer()

      assert {:error, {:mission_model_mount_required, ids}} = Compiler.compile([bus, payload])
      assert ids == [bus.layer_id, payload.layer_id]

      assert {:error, {:mission_model_mount_required, [id]}} =
               Compiler.compile([bus, payload],
                 mounts: %{bus.layer_id => "/bus", payload.layer_id => "/"}
               )

      assert id == payload.layer_id
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
