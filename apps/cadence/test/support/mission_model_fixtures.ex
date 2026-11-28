defmodule Cadence.MissionModelFixtures do
  @moduledoc false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Layer}
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison
  alias Cadence.Runtime.MissionRuntimeSpec

  def activate_imported_model!(organization_id, mission_id, result_document, opts \\ []) do
    revision_id = get_in(result_document, ["mission_model", "revision_id"])

    {:ok, candidate} =
      Cadence.MissionModels.fetch_revision(organization_id, mission_id, revision_id)

    revision =
      case candidate.status do
        :approved ->
          candidate

        :candidate ->
          {:ok, approved} =
            MissionModelApproval.approve!(organization_id, mission_id, revision_id)

          approved
      end

    {:ok, plans} =
      Cadence.MissionModels.fetch_runtime_plans(organization_id, mission_id, revision_id)

    binding_set =
      Keyword.get_lazy(opts, :binding_set, fn ->
        BindingSet.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          binding_set_id: "mission-model-test-#{System.unique_integer([:positive])}",
          version: 1
        })
      end)

    {:ok, binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    {:ok, activation} =
      Cadence.Activations.record_binding_set_activation(
        organization_id,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        binding_set_content_sha256: MissionRuntimeSpec.content_sha256(binding_set),
        metadata: %{"mission_model" => MissionModelPromotion.manifest(revision, plans)}
      )

    if Keyword.get(opts, :reconcile?, false) do
      {:ok, _mission_control} = ControlMissions.ensure_started(mission_id)

      {:ok, _generation_applied} =
        MissionRuntimeReconciler.apply_generation(mission_id, activation, binding_set)
    end

    runtime_definitions = plans.command.plan["runtime_definitions"]

    %{
      revision_id: revision_id,
      commands_by_name: Map.new(runtime_definitions, &{&1["name"], &1["command_id"]}),
      binding_set: binding_set
    }
  end

  @doc """
  Requests a mission-scope model activation of an approved revision: its manifest and a passed
  comparison against the binding set go in the request's metadata, the shape
  `Control.MissionModelPromotion` validates on approve and apply.
  """
  def request_model_activation(
        scope,
        mission_id,
        revision_id,
        binding_set_id,
        version,
        opts \\ []
      ) do
    organization_id = scope.organization_id

    with {:ok, revision} <- MissionModels.fetch_revision(organization_id, mission_id, revision_id),
         {:ok, plans} <-
           MissionModels.fetch_runtime_plans(organization_id, mission_id, revision_id),
         {:ok, %{"status" => "passed"} = comparison} <-
           Comparison.run(organization_id, mission_id, revision_id, binding_set_id, version) do
      metadata =
        opts
        |> Keyword.get(:metadata, %{})
        |> Map.put("mission_model", MissionModels.manifest(revision, plans))
        |> Map.put("mission_model_comparison", %{
          "comparison_report_id" => comparison["comparison_report_id"],
          "report_sha256" => comparison["report_sha256"]
        })

      ManagementActivations.request(scope, mission_id, binding_set_id, version,
        metadata: metadata,
        now: Keyword.get(opts, :at, DateTime.utc_now())
      )
    end
  end

  def command_id!(model, name), do: Map.fetch!(model.commands_by_name, name)

  def compile_empty_model(mission_id, organization_id \\ nil) do
    Layer.new(%{
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Minimal native Mission Model",
      declarations: [%{kind: :space_system, qualified_name: "/"}]
    })
    |> then(&Compiler.compile([&1]))
  end
end
