defmodule Cadence.MissionModels do
  @moduledoc """
  Management-plane persistence and lifecycle for immutable Mission Model layers,
  resolved revisions, diagnostics, and runtime plans.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.{Compiler, CompilerResult, Layer, Revision, RuntimePlan}
  alias Cadence.Management.Activations, as: ManagementActivations

  alias Cadence.MissionModels.{
    Comparison,
    DiagnosticRow,
    LayerRow,
    RevisionDecisions,
    RevisionLayerRow,
    RevisionRow,
    RuntimePlanRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @doc "Builds the exact revision and compiled-plan identity manifest for activation requests."
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

  @doc "Reads only admitted command artifacts within the caller's active-generation transaction."
  defdelegate command_authoring_basis(organization_id, mission_id, manifest),
    to: Cadence.MissionModels.CommandAuthoringBasis,
    as: :load

  @doc "Reads allowed enum values from the exact semantic revision used by a command."
  defdelegate command_argument_choices(organization_id, mission_id, revision_id, argument_ids),
    to: Cadence.MissionModels.CommandArgumentChoices,
    as: :load

  @doc "Reads only the named declarations (stored JSON) from one revision."
  defdelegate declarations(organization_id, mission_id, revision_id, ids),
    to: Cadence.MissionModels.DeclarationProjection,
    as: :load

  @doc "Returns the effective model revision for a spacecraft at the given time, or nil."
  @spec revision_at(binary(), binary(), binary(), DateTime.t()) :: binary() | nil
  defdelegate revision_at(organization_id, mission_id, spacecraft_id, at),
    to: Cadence.Reads.MissionModels.ActiveBasis

  @doc """
  Groups a mission's spacecraft by the effective model revision at the given time.

  A generation is effective from its runtime receipt's completion time, inclusive.
  """
  @spec revisions_at(binary(), binary(), DateTime.t()) :: %{binary() => [binary()]}
  defdelegate revisions_at(organization_id, mission_id, at),
    to: Cadence.Reads.MissionModels.ActiveBasis

  @spec compile_layers([Layer.t()], keyword()) ::
          {:ok, CompilerResult.t()} | {:error, term()}
  def compile_layers(layers, opts \\ []) when is_list(layers) and is_list(opts) do
    with {:ok, %CompilerResult{} = result} <- Compiler.compile(layers, opts),
         {:ok, result} <- keep_command_plan(result, Keyword.get(opts, :command_plan)),
         {:ok, _changes} <- persist_compilation(layers, result) do
      {:ok, result}
    end
  end

  # A revision at an authored head runs its base's command plan unchanged (P3 M2, #451; option B
  # agreed with commanding): the authored layer can't hold a command declaration, so its own
  # command plan differs from the base's only by the embedded revision id. That is checked, never
  # assumed: any other difference refuses the compile.
  defp keep_command_plan(result, nil), do: {:ok, result}

  defp keep_command_plan(
         %CompilerResult{plans: %{command: own} = plans} = result,
         %RuntimePlan{} = base
       ) do
    # The fresh plan is in memory (atom values), the base's as stored (JSON): compare both in the
    # stored form, the encoding persistence applies (commanding-eng's report on #1106).
    if without_revision(JsonDocument.encode(own.plan)) == without_revision(base.plan),
      do:
        {:ok,
         %{
           result
           | plans: %{
               plans
               | command: %{base | mission_model_revision_id: result.revision.revision_id}
             }
         }},
      else: {:error, :authored_head_changes_command_plan}
  end

  defp keep_command_plan(result, _base), do: {:ok, result}

  defp without_revision(%{} = map) when not is_struct(map),
    do:
      map
      |> Map.drop(["mission_model_revision_id", :mission_model_revision_id])
      |> Map.new(fn {k, v} -> {k, without_revision(v)} end)

  defp without_revision(list) when is_list(list), do: Enum.map(list, &without_revision/1)
  defp without_revision(value), do: value

  @doc """
  The mission composition that names `revision_id` (#542), or
  `{:error, :mission_model_revision_not_in_catalog}`: what approval, promotion requests and their
  apply require of a revision (`CompositionApproval.require/3`).
  """
  @spec require_composition(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, :mission_model_revision_not_in_catalog}
  defdelegate require_composition(organization_id, mission_id, revision_id),
    to: Cadence.MissionModels.CompositionApproval,
    as: :require

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

  @doc """
  Holds `revision_ids` FOR SHARE until the caller's transaction ends, so a decision on one of them
  (`RevisionDecisions`, FOR UPDATE) waits: an activation approval that just checked the model gate
  can't have it change before its record (director 11-17). Must run inside a transaction.
  """
  @spec share_lock_revisions(binary(), binary(), [binary()]) :: :ok
  def share_lock_revisions(_organization_id, _mission_id, []), do: :ok

  def share_lock_revisions(organization_id, mission_id, revision_ids) do
    RevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.revision_id in ^revision_ids
    )
    |> lock("FOR SHARE")
    |> select([row], row.revision_id)
    |> Repo.all()

    :ok
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

  @doc "The status of each of `revision_ids` (one query, no documents decoded): `%{id => status}`."
  @spec revision_statuses(binary(), binary(), [binary()]) :: %{binary() => atom()}
  def revision_statuses(_organization_id, _mission_id, []), do: %{}

  def revision_statuses(organization_id, mission_id, revision_ids) do
    RevisionRow
    |> where([row], row.mission_id == ^mission_id and row.revision_id in ^revision_ids)
    |> organization_filter(organization_id)
    |> select([row], {row.revision_id, row.status})
    |> Repo.all()
    |> Map.new(fn {id, status} -> {id, String.to_existing_atom(status)} end)
  end

  @doc """
  The status each of `revision_ids` has for running it: its stored status, or for a revision at
  an authored head, the status derived from its composition's base and the head (P3 M1, #451;
  `MissionModels.EffectiveStatuses`). The model gate and every reader that decides whether a
  revision may run use this, never `revision_statuses/3` alone.
  """
  @spec effective_statuses(binary(), binary(), [binary()]) :: %{binary() => atom()}
  defdelegate effective_statuses(organization_id, mission_id, revision_ids),
    to: Cadence.MissionModels.EffectiveStatuses,
    as: :statuses

  @doc """
  The revision whose approval each of `revision_ids` carries (P3 M1, #451): a revision at an
  authored head maps to its base, any other to itself. For withdrawal reads (E2): a withdrawn
  base reaches every craft running a head built on it.
  """
  @spec approval_bases(binary(), binary(), [binary()]) :: %{binary() => binary() | nil}
  defdelegate approval_bases(organization_id, mission_id, revision_ids),
    to: Cadence.MissionModels.EffectiveStatuses

  @doc "The authored head each of `revision_ids` is linked at, nil for a base (P3 M2, #451)."
  @spec authored_heads(binary(), binary(), [binary()]) :: %{binary() => binary() | nil}
  defdelegate authored_heads(organization_id, mission_id, revision_ids),
    to: Cadence.MissionModels.EffectiveStatuses

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
    targets = [:telemetry, :algorithm, :monitoring, :command]
    names = Enum.map(targets, &Atom.to_string/1)

    # One read for the four plans (a request loads the basis several times). The error is still the
    # first missing target in this order.
    found =
      RuntimePlanRow
      |> where(
        [row],
        row.mission_id == ^mission_id and row.revision_id == ^revision_id and
          row.target in ^names
      )
      |> organization_filter(organization_id)
      |> Repo.all()
      |> Map.new(&{&1.target, &1})

    Enum.reduce_while(targets, {:ok, %{}}, fn target, {:ok, plans} ->
      case Map.fetch(found, Atom.to_string(target)) do
        {:ok, row} -> {:cont, {:ok, Map.put(plans, target, RuntimePlanRow.to_domain(row))}}
        :error -> {:halt, {:error, {target, :mission_model_runtime_plan_not_found}}}
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
         {:ok, _composition} <- require_composition(organization_id, mission_id, revision_id),
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
        |> Map.put("mission_model", manifest(revision, plans))
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

  @doc "Approves a candidate revision; see `Cadence.MissionModels.RevisionDecisions`."
  defdelegate approve_revision(scope, mission_id, revision_id, comparison_report_id, opts \\ []),
    to: RevisionDecisions,
    as: :approve

  @doc "Rejects a revision; see `Cadence.MissionModels.RevisionDecisions`."
  defdelegate reject_revision(scope, mission_id, revision_id, reason, opts \\ []),
    to: RevisionDecisions,
    as: :reject

  @doc "A withdrawn revision's withdrawal record, or nil (E2, #546)."
  defdelegate revision_withdrawal(organization_id, mission_id, revision_id),
    to: RevisionDecisions,
    as: :withdrawal

  @doc "People's model decisions in the mission, for the organization audit."
  defdelegate list_model_decisions(organization_id, mission_id),
    to: RevisionDecisions,
    as: :list_decisions

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

  defp require_passed_comparison(%{"status" => "passed"}), do: :ok
  defp require_passed_comparison(_comparison), do: {:error, :mission_model_comparison_not_passed}

  defp organization_filter(query, nil), do: where(query, [row], is_nil(row.organization_id))

  defp organization_filter(query, organization_id),
    do: where(query, [row], row.organization_id == ^organization_id)

  defp status_filter(query, nil), do: query

  defp status_filter(query, status),
    do: where(query, [row], row.status == ^Atom.to_string(status))
end
