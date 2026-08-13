defmodule Cadence.Control.MissionModelPromotion do
  @moduledoc """
  Explicit promotion boundary for an atomic Mission Model and binding-set
  runtime generation.

  The durable activation metadata contains the exact revision and plan
  identities. Reconciliation resolves those immutable artifacts and refuses
  drift before handing a complete specification to the data plane.
  """

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Catalog.MissionModel.{Revision, RuntimePlan}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison

  @targets [:telemetry, :algorithm, :monitoring, :command]

  @spec promote(binary(), binary(), binary(), binary(), pos_integer(), map(), map(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def promote(
        _organization_id,
        _mission_id,
        _revision_id,
        _binding_set_id,
        _binding_set_version,
        _comparison_report,
        _actor,
        _opts \\ []
      ),
      do: {:error, :mission_model_activation_request_required}

  @doc false
  def validate_activation_metadata(organization_id, mission_id, binding_set, metadata) do
    case value(metadata, :mission_model) do
      nil ->
        :ok

      manifest when is_map(manifest) ->
        comparison_ref = value(metadata, :mission_model_comparison, %{})

        with comparison_id when is_binary(comparison_id) and comparison_id != "" <-
               value(comparison_ref, :comparison_report_id),
             {:ok, comparison} <- Comparison.fetch(organization_id, mission_id, comparison_id),
             :ok <- exact_value(comparison["status"], "passed", :comparison_status),
             :ok <-
               exact_value(
                 comparison["report_sha256"],
                 value(comparison_ref, :report_sha256),
                 :comparison_content
               ),
             :ok <-
               exact_value(
                 comparison["candidate_revision_id"],
                 value(manifest, :revision_id),
                 :comparison_revision
               ),
             :ok <-
               exact_value(
                 comparison["binding_set_id"],
                 binding_set.binding_set_id,
                 :comparison_binding_set
               ),
             :ok <-
               exact_value(
                 comparison["binding_set_version"],
                 binding_set.version,
                 :comparison_binding_set_version
               ),
             {:ok, %Revision{status: :approved} = revision} <-
               MissionModels.fetch_revision(
                 organization_id,
                 mission_id,
                 value(manifest, :revision_id)
               ),
             {:ok, plans} <-
               MissionModels.fetch_runtime_plans(
                 organization_id,
                 mission_id,
                 revision.revision_id
               ),
             :ok <- exact_plan_manifest(plans, value(manifest, :plans, %{})),
             :ok <- require_ready_plans(plans) do
          :ok
        else
          {:ok, %Revision{}} -> {:error, :mission_model_revision_not_approved}
          nil -> {:error, :mission_model_comparison_report_required}
          false -> {:error, :mission_model_comparison_report_required}
          {:error, reason} -> {:error, reason}
        end

      _other ->
        {:error, :invalid_mission_model_activation_manifest}
    end
  end

  @doc false
  @spec runtime_basis(BindingSetActivation.t()) ::
          {:ok,
           %{
             optional(:mission_model_revision_id) => binary(),
             optional(:mission_model_content_sha256) => binary(),
             optional(:runtime_plans) => %{atom() => RuntimePlan.t()}
           }}
          | {:error, term()}
  def runtime_basis(%BindingSetActivation{} = activation) do
    case value(activation.metadata, :mission_model) do
      nil ->
        {:ok, %{}}

      manifest when is_map(manifest) ->
        resolve_runtime_basis(activation, manifest)

      _other ->
        {:error, :invalid_mission_model_activation_manifest}
    end
  end

  defp resolve_runtime_basis(activation, manifest) do
    revision_id = value(manifest, :revision_id)
    expected_revision_hash = value(manifest, :content_sha256)
    expected_plans = value(manifest, :plans, %{})

    with true <- is_binary(revision_id) and revision_id != "",
         true <- is_binary(expected_revision_hash) and expected_revision_hash != "",
         true <- is_map(expected_plans),
         {:ok, %Revision{} = revision} <-
           MissionModels.fetch_revision(
             activation.organization_id,
             activation.mission_id,
             revision_id
           ),
         :ok <- exact_value(revision.content_sha256, expected_revision_hash, :revision_content),
         {:ok, plans} <-
           MissionModels.fetch_runtime_plans(
             activation.organization_id,
             activation.mission_id,
             revision_id
           ),
         :ok <- exact_plan_manifest(plans, expected_plans),
         :ok <- require_ready_plans(plans) do
      {:ok,
       %{
         mission_model_revision_id: revision.revision_id,
         mission_model_content_sha256: revision.content_sha256,
         runtime_plans: plans
       }}
    else
      false -> {:error, :invalid_mission_model_activation_manifest}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def manifest(revision, plans) do
    %{
      "revision_id" => revision.revision_id,
      "content_sha256" => revision.content_sha256,
      "plans" =>
        Map.new(plans, fn {target, plan} ->
          {Atom.to_string(target),
           %{
             "plan_id" => plan.plan_id,
             "content_sha256" => plan.content_sha256,
             "target_contract_version" => plan.target_contract_version
           }}
        end)
    }
  end

  defp exact_plan_manifest(plans, expected) do
    if Enum.all?(@targets, &exact_plan?(&1, plans, expected)) do
      :ok
    else
      {:error, :mission_model_runtime_plan_manifest_mismatch}
    end
  end

  defp exact_plan?(target, plans, expected) do
    plan = Map.get(plans, target)
    recorded = Map.get(expected, Atom.to_string(target), Map.get(expected, target))

    match?(%RuntimePlan{}, plan) and is_map(recorded) and
      value(recorded, :plan_id) == plan.plan_id and
      value(recorded, :content_sha256) == plan.content_sha256 and
      value(recorded, :target_contract_version) == plan.target_contract_version
  end

  defp require_ready_plans(plans) when map_size(plans) == 4 do
    if Enum.all?(@targets, &match?(%RuntimePlan{status: :ready}, Map.get(plans, &1))) do
      :ok
    else
      {:error, :mission_model_runtime_plans_not_ready}
    end
  end

  defp require_ready_plans(_plans), do: {:error, :mission_model_runtime_plans_not_ready}

  defp exact_value(value, value, _field), do: :ok

  defp exact_value(_value, _expected, field),
    do: {:error, {:mission_model_manifest_mismatch, field}}

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
