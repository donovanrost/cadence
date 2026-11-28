defmodule Cadence.Catalog.MissionModelCompilerTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{
    Compiler,
    Declaration,
    Layer,
    Reference,
    Revision
  }

  test "compiles the same exact layers deterministically" do
    layer = layer_with_relative_reference()

    assert {:ok, first} = Compiler.compile([layer])
    assert {:ok, second} = Compiler.compile([layer])

    assert %Revision{} = first.revision
    assert first.revision.revision_id == second.revision.revision_id
    assert first.revision.content_sha256 == second.revision.content_sha256
    assert first.plans.telemetry.content_sha256 == second.plans.telemetry.content_sha256
    assert first.plans.telemetry.status == :ready
  end

  describe "plan identity is the plan's, not the revision's (#443)" do
    test "a revision that leaves a target's plan alone leaves its id alone" do
      raw = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/raw"})
      out = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/out"})
      other = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/other"})

      without = layer("v1", [raw, out])
      with_algorithm = layer("v2", [raw, out, algorithm("/algorithms/a", raw, out)])

      assert {:ok, first} = Compiler.compile([without])
      assert {:ok, second} = Compiler.compile([with_algorithm])
      assert {:ok, third} = Compiler.compile([layer("v3", [raw, out, other])])

      # Three different revisions, each with its own layer and revision ids.
      assert length(Enum.uniq([first, second, third] |> Enum.map(& &1.revision.revision_id))) == 3

      # The algorithm was added: only the algorithm plan moved.
      assert second.plans.telemetry.plan_id == first.plans.telemetry.plan_id
      assert second.plans.telemetry.content_sha256 == first.plans.telemetry.content_sha256
      assert second.plans.monitoring.plan_id == first.plans.monitoring.plan_id
      refute second.plans.algorithm.plan_id == first.plans.algorithm.plan_id

      # A parameter no plan uses was added: a new revision, every plan the same.
      for target <- [:telemetry, :monitoring, :command, :algorithm] do
        assert third.plans[target].plan_id == first.plans[target].plan_id
      end

      # What a plan was compiled under stays on it, per revision.
      assert first.plans.telemetry.mission_model_revision_id == first.revision.revision_id
      assert second.plans.telemetry.mission_model_revision_id == second.revision.revision_id

      refute first.plans.telemetry.mission_model_revision_id ==
               second.plans.telemetry.mission_model_revision_id
    end

    test "the organization and the mission are part of the id" do
      declarations = [Declaration.new(%{kind: :parameter, qualified_name: "/parameters/raw"})]

      plan_ids = fn org, mission ->
        layer =
          Layer.new(%{
            organization_id: org,
            mission_id: mission,
            name: "same",
            declarations: systems(["/"]) ++ declarations
          })

        {:ok, result} = Compiler.compile([layer])
        result.plans.telemetry.plan_id
      end

      same = plan_ids.("org-a", "mission-a")
      assert plan_ids.("org-a", "mission-a") == same
      refute plan_ids.("org-b", "mission-a") == same
      refute plan_ids.("org-a", "mission-b") == same
    end

    test "a blocked plan and a ready one with the same body are not the same plan" do
      parameter = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/mode"})

      dangling =
        Declaration.new(%{
          kind: :parameter,
          qualified_name: "/parameters/dangling",
          references: [%{expected_kind: :parameter_type, source_ref: "/types/missing"}]
        })

      assert {:ok, ready} = Compiler.compile([layer("ready", [parameter])])
      assert {:ok, blocked} = Compiler.compile([layer("blocked", [parameter, dangling])])

      assert ready.plans.monitoring.status == :ready
      assert blocked.plans.monitoring.status == :blocked
      refute ready.plans.monitoring.plan_id == blocked.plans.monitoring.plan_id
    end
  end

  test "resolves local, relative, and absolute references to stable identities" do
    parameter =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: "/vehicle/pobc/parameters/temperature",
        references: [
          %{expected_kind: :parameter_type, source_ref: "../types/temperature"},
          %{expected_kind: :unit, source_ref: "/vehicle/units/celsius"}
        ]
      })

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "hierarchy",
        declarations:
          systems(["/", "/vehicle", "/vehicle/pobc"]) ++
            [
              %{kind: :unit, qualified_name: "/vehicle/units/celsius"},
              %{kind: :parameter_type, qualified_name: "/vehicle/pobc/types/temperature"},
              parameter
            ]
      })

    assert {:ok, result} = Compiler.compile([layer])
    resolved = result.revision.declarations[parameter.semantic_id]

    assert Enum.all?(resolved.references, &is_binary(&1.resolved_id))

    assert Enum.map(resolved.references, & &1.resolved_qualified_name) == [
             "/vehicle/pobc/types/temperature",
             "/vehicle/units/celsius"
           ]
  end

  test "reports dangling and wrong-kind references with stable codes" do
    parameter =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: "/parameters/mode",
        references: [
          %{expected_kind: :parameter_type, source_ref: "/types/missing"},
          %{expected_kind: :parameter_type, source_ref: "/units/count"}
        ]
      })

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "invalid",
        declarations:
          systems(["/"]) ++ [%{kind: :unit, qualified_name: "/units/count"}, parameter]
      })

    assert {:ok, result} = Compiler.compile([layer])

    assert MapSet.new(Enum.map(result.revision.diagnostics, & &1.code)) ==
             MapSet.new(["MM_REFERENCE_DANGLING", "MM_REFERENCE_WRONG_KIND"])

    assert result.plans.telemetry.status == :blocked
  end

  test "authored replacements require the exact prior fingerprint" do
    original = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/mode"})

    imported =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "imported",
        declarations: systems(["/"]) ++ [original]
      })

    replacement =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: original.qualified_name,
        operation: :replace,
        expected_fingerprint: Declaration.fingerprint(original),
        definition: %{source: :derived}
      })

    authored =
      Layer.new(%{
        mission_id: "mission-alpha",
        layer_kind: :authored,
        name: "operator edit",
        declarations: [replacement]
      })

    assert {:ok, result} = Compiler.compile([imported, authored])
    assert result.revision.diagnostics == []
    assert result.revision.declarations[original.semantic_id].definition == %{source: :derived}
  end

  test "duplicate additions never silently overwrite" do
    declaration = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/mode"})

    imported =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "imported",
        declarations: systems(["/"]) ++ [declaration]
      })

    # Authored, so it addresses the import's own tree. Two imported layers need a mount each
    # (#444; mission_model_mount_test.exs covers duplicates across mounted imports).
    duplicate =
      Layer.new(%{
        mission_id: "mission-alpha",
        layer_kind: :authored,
        name: "duplicate",
        declarations: [declaration]
      })

    assert {:ok, result} = Compiler.compile([imported, duplicate])
    assert Enum.any?(result.revision.diagnostics, &(&1.code == "MM_DUPLICATE_IDENTITY"))
  end

  test "orders algorithms by parameter dependencies and rejects producer cycles" do
    first_parameter =
      Declaration.new(%{kind: :parameter, qualified_name: "/parameters/first"})

    second_parameter =
      Declaration.new(%{kind: :parameter, qualified_name: "/parameters/second"})

    first_algorithm =
      algorithm("/algorithms/first", second_parameter, first_parameter)

    second_algorithm =
      algorithm("/algorithms/second", first_parameter, second_parameter)

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "cyclic algorithms",
        declarations:
          systems(["/"]) ++
            [first_parameter, second_parameter, first_algorithm, second_algorithm]
      })

    assert {:ok, result} = Compiler.compile([layer])
    assert Enum.any?(result.revision.diagnostics, &(&1.code == "MM_ALGORITHM_CYCLE"))
    assert result.plans.algorithm.status == :blocked
  end

  test "lowers an acyclic algorithm graph in dependency order" do
    raw = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/raw"})
    first = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/first"})
    second = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/second"})

    producer = algorithm("/algorithms/z_producer", raw, first)
    consumer = algorithm("/algorithms/a_consumer", first, second)

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "ordered algorithms",
        declarations: systems(["/"]) ++ [raw, first, second, consumer, producer]
      })

    assert {:ok, result} = Compiler.compile([layer])

    assert Enum.map(result.plans.algorithm.plan["algorithms"], & &1["algorithm_id"]) == [
             producer.semantic_id,
             consumer.semantic_id
           ]
  end

  test "applies observable defaults and materializes command inheritance" do
    base =
      Declaration.new(%{
        kind: :command,
        qualified_name: "/commands/base",
        definition: %{opcode: 7, metadata: %{family: "bus"}}
      })

    child =
      Declaration.new(%{
        kind: :command,
        qualified_name: "/commands/child",
        definition: %{metadata: %{variant: "payload"}},
        references: [
          %{expected_kind: :command, source_ref: base.qualified_name, role: :base}
        ]
      })

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "command inheritance",
        declarations: systems(["/"]) ++ [base, child]
      })

    assert {:ok, result} = Compiler.compile([layer])
    resolved = result.revision.declarations[child.semantic_id]

    assert resolved.definition == %{
             opcode: 7,
             abstract: false,
             metadata: %{family: "bus", variant: "payload"}
           }

    assert resolved.extensions["cadence_compiler"]["defaults_applied"] == ["abstract"]
    assert resolved.extensions["cadence_compiler"]["inherited_from"] == base.semantic_id
  end

  test "rejects inheritance cycles and duplicate qualified names" do
    first =
      Declaration.new(%{
        semantic_id: "command:first",
        kind: :command,
        qualified_name: "/commands/shared",
        references: [
          %{expected_kind: :command, source_ref: "/commands/second", role: :base}
        ]
      })

    second =
      Declaration.new(%{
        semantic_id: "command:second",
        kind: :command,
        qualified_name: "/commands/second",
        references: [
          %{expected_kind: :command, source_ref: "/commands/shared", role: :base}
        ]
      })

    duplicate =
      Declaration.new(%{
        semantic_id: "command:duplicate",
        kind: :command,
        qualified_name: "/commands/shared"
      })

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "invalid inheritance",
        declarations: systems(["/"]) ++ [first, second, duplicate]
      })

    assert {:ok, result} = Compiler.compile([layer])
    codes = MapSet.new(result.revision.diagnostics, & &1.code)

    assert "MM_INHERITANCE_CYCLE" in codes
    assert "MM_DUPLICATE_QUALIFIED_NAME" in codes
    assert result.plans.command.status == :blocked
  end

  test "rejects invalid timer semantics before lowering" do
    algorithm =
      Declaration.new(%{
        kind: :algorithm,
        qualified_name: "/algorithms/timer",
        definition: %{
          implementation: %{kind: :expression},
          triggers: [%{kind: :periodic, interval_ms: 0}]
        }
      })

    layer =
      Layer.new(%{
        mission_id: "mission-alpha",
        name: "invalid timer",
        declarations: systems(["/"]) ++ [algorithm]
      })

    assert {:ok, result} = Compiler.compile([layer])
    assert Enum.any?(result.revision.diagnostics, &(&1.code == "MM_ALGORITHM_TRIGGER_INVALID"))
    assert result.plans.algorithm.status == :blocked
  end

  defp layer_with_relative_reference do
    Layer.new(%{
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      name: "deterministic",
      declarations:
        systems(["/", "/vehicle"]) ++
          [
            %{kind: :parameter_type, qualified_name: "/vehicle/types/temperature"},
            %{
              kind: :parameter,
              qualified_name: "/vehicle/parameters/temperature",
              references: [
                Reference.new(%{
                  expected_kind: :parameter_type,
                  source_ref: "../types/temperature",
                  role: :type
                })
              ]
            }
          ]
    })
  end

  defp layer(name, declarations) do
    Layer.new(%{
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      name: name,
      declarations: systems(["/"]) ++ declarations
    })
  end

  defp systems(paths) do
    Enum.map(paths, &%{kind: :space_system, qualified_name: &1})
  end

  defp algorithm(path, input, output) do
    Declaration.new(%{
      kind: :algorithm,
      qualified_name: path,
      references: [
        %{expected_kind: :parameter, source_ref: input.qualified_name, role: :input},
        %{expected_kind: :parameter, source_ref: output.qualified_name, role: :output}
      ],
      definition: %{
        implementation: %{kind: :expression},
        outputs: [
          %{
            parameter_id: output.semantic_id,
            qualified_name: output.qualified_name,
            expression: %{node: {:parameter, input.semantic_id}, result_type: :number}
          }
        ]
      }
    })
  end
end
