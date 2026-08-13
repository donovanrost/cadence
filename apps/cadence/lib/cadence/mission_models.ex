defmodule Cadence.MissionModels do
  @moduledoc """
  Management-plane persistence and lifecycle for immutable Mission Model layers,
  resolved revisions, diagnostics, and runtime plans.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.{Compiler, CompilerResult, Layer, Revision, RuntimePlan}
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Management.Activations, as: ManagementActivations

  alias Cadence.MissionModels.{
    Comparison,
    DiagnosticRow,
    LayerRow,
    RevisionLayerRow,
    RevisionRow,
    RuntimePlanRow
  }

  alias Cadence.MissionModels.LegacyMigration

  alias Cadence.Repo

  @spec compile_layers([Layer.t()], keyword()) ::
          {:ok, CompilerResult.t()} | {:error, term()}
  def compile_layers(layers, opts \\ []) when is_list(layers) and is_list(opts) do
    with {:ok, %CompilerResult{} = result} <- Compiler.compile(layers, opts),
         {:ok, _changes} <- persist_compilation(layers, result) do
      {:ok, result}
    end
  end

  @spec compose(binary(), binary(), [binary()], keyword()) ::
          {:ok, CompilerResult.t()} | {:error, term()}
  def compose(organization_id, mission_id, layer_ids, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(layer_ids) do
    with {:ok, layers} <- fetch_layers_in_order(organization_id, mission_id, layer_ids) do
      compile_layers(layers, opts)
    end
  end

  @spec persist_layer(Layer.t()) :: {:ok, Layer.t()} | {:error, term()}
  def persist_layer(%Layer{} = layer) do
    case Repo.insert(LayerRow.changeset(layer), on_conflict: :nothing) do
      {:ok, _row} -> fetch_layer(layer.organization_id, layer.mission_id, layer.layer_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_layer(binary() | nil, binary(), binary()) :: {:ok, Layer.t()} | {:error, term()}
  def fetch_layer(organization_id, mission_id, layer_id)
      when is_binary(mission_id) and is_binary(layer_id) do
    LayerRow
    |> where([row], row.mission_id == ^mission_id and row.layer_id == ^layer_id)
    |> organization_filter(organization_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :mission_model_layer_not_found}
      row -> {:ok, LayerRow.to_domain(row)}
    end
  end

  @spec list_layers(binary() | nil, binary()) :: [Layer.t()]
  def list_layers(organization_id, mission_id) when is_binary(mission_id) do
    LayerRow
    |> where([row], row.mission_id == ^mission_id)
    |> organization_filter(organization_id)
    |> order_by([row], asc: row.inserted_at, asc: row.layer_id)
    |> Repo.all()
    |> Enum.map(&LayerRow.to_domain/1)
  end

  @spec fetch_revision(binary() | nil, binary(), binary()) ::
          {:ok, Revision.t()} | {:error, term()}
  def fetch_revision(organization_id, mission_id, revision_id)
      when is_binary(mission_id) and is_binary(revision_id) do
    RevisionRow
    |> where([row], row.mission_id == ^mission_id and row.revision_id == ^revision_id)
    |> organization_filter(organization_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :mission_model_revision_not_found}
      row -> {:ok, RevisionRow.to_domain(row)}
    end
  end

  @spec list_revisions(binary() | nil, binary(), keyword()) :: [Revision.t()]
  def list_revisions(organization_id, mission_id, opts \\ []) when is_binary(mission_id) do
    RevisionRow
    |> where([row], row.mission_id == ^mission_id)
    |> organization_filter(organization_id)
    |> status_filter(Keyword.get(opts, :status))
    |> order_by([row], desc: row.inserted_at, desc: row.revision_id)
    |> Repo.all()
    |> Enum.map(&RevisionRow.to_domain/1)
  end

  @spec fetch_plan(binary() | nil, binary(), binary(), atom()) ::
          {:ok, RuntimePlan.t()} | {:error, term()}
  def fetch_plan(organization_id, mission_id, revision_id, target)
      when is_binary(mission_id) and is_binary(revision_id) and is_atom(target) do
    RuntimePlanRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.revision_id == ^revision_id and
        row.target == ^Atom.to_string(target)
    )
    |> organization_filter(organization_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :mission_model_runtime_plan_not_found}
      row -> {:ok, RuntimePlanRow.to_domain(row)}
    end
  end

  @spec fetch_runtime_plans(binary() | nil, binary(), binary()) ::
          {:ok, %{required(atom()) => RuntimePlan.t()}} | {:error, term()}
  def fetch_runtime_plans(organization_id, mission_id, revision_id)
      when is_binary(mission_id) and is_binary(revision_id) do
    [:telemetry, :algorithm, :monitoring, :command]
    |> Enum.reduce_while({:ok, %{}}, fn target, {:ok, plans} ->
      case fetch_plan(organization_id, mission_id, revision_id, target) do
        {:ok, plan} -> {:cont, {:ok, Map.put(plans, target, plan)}}
        {:error, reason} -> {:halt, {:error, {target, reason}}}
      end
    end)
  end

  @doc """
  Computes and persists the candidate comparison, then creates an authenticated
  activation request. Approval and execution remain owned by the existing
  management/control activation workflow.
  """
  @spec request_promotion(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          keyword()
        ) :: {:ok, Cadence.Management.Activations.ActivationRequest.t()} | {:error, term()}
  def request_promotion(
        %Scope{} = current_scope,
        mission_id,
        revision_id,
        binding_set_id,
        binding_set_version,
        opts \\ []
      ) do
    organization_id = current_scope.organization_id

    with {:ok, %Revision{status: :approved} = revision} <-
           fetch_revision(organization_id, mission_id, revision_id),
         {:ok, plans} <- fetch_runtime_plans(organization_id, mission_id, revision_id),
         {:ok, comparison} <-
           Comparison.run(
             organization_id,
             mission_id,
             revision_id,
             binding_set_id,
             binding_set_version
           ),
         :ok <- require_passed_comparison(comparison) do
      metadata =
        opts
        |> Keyword.get(:metadata, %{})
        |> Map.put("mission_model", MissionModelPromotion.manifest(revision, plans))
        |> Map.put("mission_model_comparison", %{
          "comparison_report_id" => comparison["comparison_report_id"],
          "report_sha256" => comparison["report_sha256"]
        })

      ManagementActivations.request(
        current_scope,
        mission_id,
        binding_set_id,
        binding_set_version,
        change_class: :mission_data_plane,
        metadata: metadata,
        now: Keyword.get(opts, :at, DateTime.utc_now())
      )
    else
      {:ok, %Revision{}} -> {:error, :mission_model_revision_not_approved}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Registers an approved, mission-scoped replay case for high-risk comparisons."
  def register_qualification_case(%Scope{} = current_scope, mission_id, name, updates, opts \\ []) do
    Comparison.register_case(current_scope, mission_id, name, updates, opts)
  end

  @deprecated "Use request_promotion/6 and the authenticated activation approval workflow"
  def promote_revision(
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

  @doc """
  Converts the latest transitional Derived Telemetry and Limits definitions
  into one immutable authored layer on an exact base revision.
  """
  @spec convert_legacy_definitions(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, CompilerResult.t()} | {:error, term()}
  def convert_legacy_definitions(organization_id, mission_id, base_revision_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(base_revision_id) and is_map(actor) and is_list(opts) do
    LegacyMigration.convert(organization_id, mission_id, base_revision_id, actor, opts)
  end

  @spec approve_revision(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def approve_revision(organization_id, mission_id, revision_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) and
             is_map(actor) do
    with {:ok, %Revision{} = revision} <- fetch_revision(organization_id, mission_id, revision_id),
         :ok <- require_approvable(revision),
         :ok <- require_ready_plans(organization_id, mission_id, revision_id),
         {:ok, row} <- fetch_revision_row(organization_id, mission_id, revision_id),
         {:ok, approved_row} <-
           row
           |> RevisionRow.status_changeset(
             :approved,
             actor,
             normalized_datetime(Keyword.get(opts, :at, DateTime.utc_now()))
           )
           |> Repo.update() do
      {:ok, RevisionRow.to_domain(approved_row)}
    end
  end

  @spec reject_revision(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def reject_revision(organization_id, mission_id, revision_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) and
             is_map(actor) do
    with {:ok, row} <- fetch_revision_row(organization_id, mission_id, revision_id),
         {:ok, rejected_row} <-
           row
           |> RevisionRow.status_changeset(
             :rejected,
             actor,
             normalized_datetime(Keyword.get(opts, :at, DateTime.utc_now()))
           )
           |> Repo.update() do
      {:ok, RevisionRow.to_domain(rejected_row)}
    end
  end

  defp persist_compilation(layers, %CompilerResult{} = result) do
    multi =
      Enum.reduce(layers, Multi.new(), fn layer, acc ->
        Multi.insert(acc, {:mission_model_layer, layer.layer_id}, LayerRow.changeset(layer),
          on_conflict: :nothing
        )
      end)
      |> Multi.insert(:mission_model_revision, RevisionRow.changeset(result.revision),
        on_conflict: :nothing
      )
      |> add_revision_layers(result.revision)
      |> add_revision_diagnostics(result.revision)
      |> add_runtime_plans(result)

    Repo.transaction(multi)
  end

  defp add_revision_layers(multi, revision) do
    revision.layer_ids
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {layer_id, position}, acc ->
      Multi.insert(
        acc,
        {:mission_model_revision_layer, position},
        RevisionLayerRow.changeset(revision.revision_id, layer_id, position),
        on_conflict: :nothing
      )
    end)
  end

  defp add_revision_diagnostics(multi, revision) do
    revision.diagnostics
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {diagnostic, index}, acc ->
      changeset = DiagnosticRow.changeset(revision, diagnostic)

      Multi.insert(acc, {:mission_model_diagnostic, index}, changeset, on_conflict: :nothing)
    end)
  end

  defp add_runtime_plans(multi, %CompilerResult{} = result) do
    Enum.reduce(result.plans, multi, fn {target, plan}, acc ->
      acc
      |> Multi.insert(
        {:mission_model_runtime_plan, target},
        RuntimePlanRow.changeset(result.revision, plan),
        on_conflict: :nothing
      )
      |> add_plan_diagnostics(result.revision, plan)
    end)
  end

  defp add_plan_diagnostics(multi, revision, plan) do
    plan.diagnostics
    |> Enum.filter(&(&1.target == plan.target))
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {diagnostic, index}, acc ->
      changeset = DiagnosticRow.changeset(revision, diagnostic, plan_id: plan.plan_id)

      Multi.insert(
        acc,
        {:mission_model_plan_diagnostic, plan.target, index},
        changeset,
        on_conflict: :nothing
      )
    end)
  end

  defp fetch_layers_in_order(organization_id, mission_id, layer_ids) do
    layer_ids
    |> Enum.reduce_while({:ok, []}, fn layer_id, {:ok, acc} ->
      case fetch_layer(organization_id, mission_id, layer_id) do
        {:ok, layer} -> {:cont, {:ok, [layer | acc]}}
        {:error, reason} -> {:halt, {:error, {layer_id, reason}}}
      end
    end)
    |> case do
      {:ok, layers} -> {:ok, Enum.reverse(layers)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_revision_row(organization_id, mission_id, revision_id) do
    case Repo.get_by(RevisionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           revision_id: revision_id
         ) do
      nil -> {:error, :mission_model_revision_not_found}
      row -> {:ok, row}
    end
  end

  defp require_approvable(%Revision{status: :candidate}), do: :ok
  defp require_approvable(%Revision{status: :approved}), do: :ok
  defp require_approvable(%Revision{}), do: {:error, :mission_model_revision_not_approvable}

  defp require_passed_comparison(%{"status" => "passed"}), do: :ok
  defp require_passed_comparison(_comparison), do: {:error, :mission_model_comparison_not_passed}

  defp require_ready_plans(organization_id, mission_id, revision_id) do
    statuses =
      RuntimePlanRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> select([row], row.status)
      |> Repo.all()

    if length(statuses) == 4 and Enum.all?(statuses, &(&1 == "ready")) do
      :ok
    else
      {:error, :mission_model_runtime_plans_not_ready}
    end
  end

  defp organization_filter(query, nil), do: where(query, [row], is_nil(row.organization_id))

  defp organization_filter(query, organization_id),
    do: where(query, [row], row.organization_id == ^organization_id)

  defp status_filter(query, nil), do: query

  defp status_filter(query, status),
    do: where(query, [row], row.status == ^Atom.to_string(status))

  defp normalized_datetime(%DateTime{} = datetime) do
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
