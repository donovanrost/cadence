# Run this helper in a separate VM. Atom literals for diagnostic values, ExUnit,
# or compiling a fixture here would hide the module-loading regression.
compiler_modules = [
  Cadence.Catalog.MissionModel.Compiler,
  Cadence.Catalog.MissionModel.Target,
  Cadence.Catalog.MissionModel.TargetLowering,
  Cadence.Catalog.MissionModel.Inheritance,
  Cadence.Catalog.MissionModel.Validator
]

for module <- compiler_modules, do: false = :code.is_loaded(module)

stages = [
  "legalization",
  "target_lowering",
  "source_validation",
  "namespace",
  "composition",
  "reference_resolution",
  "inheritance",
  "graph",
  "semantic_validation"
]

for stage <- stages,
    target <- ["telemetry", "algorithm", "monitoring", "command"],
    support <- ["exact", "transformed", "preserved", "lossy", "invalid"] do
  plan =
    Cadence.Catalog.MissionModel.RuntimePlan.from_map(%{
      "plan_id" => "stored-plan",
      "target" => target,
      "status" => "ready",
      "diagnostics" => [
        %{
          "code" => "MM_ALGORITHM_IMPLEMENTATION_UNSUPPORTED",
          "severity" => "warning",
          "stage" => stage,
          "target" => target,
          "support" => support,
          "message" => "Preserved declaration"
        }
      ]
    })

  [diagnostic] = plan.diagnostics
  ^stage = Atom.to_string(diagnostic.stage)
  ^target = Atom.to_string(diagnostic.target)
  ^support = Atom.to_string(diagnostic.support)
  "warning" = Atom.to_string(diagnostic.severity)
  "ready" = Atom.to_string(plan.status)
  ^target = Atom.to_string(plan.target)
end

for module <- compiler_modules, do: false = :code.is_loaded(module)
IO.puts("MISSION_MODEL_COLD_DECODE_OK")
