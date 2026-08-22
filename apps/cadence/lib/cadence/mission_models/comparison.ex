defmodule Cadence.MissionModels.Comparison do
  @moduledoc "Static and replay qualification for Mission Model activation candidates."

  import Ecto.Query

  alias Cadence.Activations
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog.MissionModel.{Declaration, Revision, RuntimePlan}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{ComparisonReportRow, QualificationCaseRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, Result, State, Update}

  @high_risk_kinds [
    :container,
    :calibrator,
    :algorithm,
    :monitoring_policy,
    :command_argument_type,
    :command_argument,
    :command_encoding,
    :command,
    :command_constraint,
    :command_verifier,
    :stream,
    :service,
    :extension
  ]
  @medium_risk_kinds [:parameter_type, :parameter, :unit]

  @spec register_case(Scope.t(), binary(), binary(), [Update.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def register_case(%Scope{} = scope, mission_id, name, updates, opts \\ [])
      when is_binary(mission_id) and is_binary(name) and is_list(updates) and is_list(opts) do
    with :ok <-
           Policy.authorize(scope, :request_activation, %{
             organization_id: scope.organization_id,
             mission_id: mission_id,
             change_class: :mission_data_plane
           }),
         true <- updates != [] and Enum.all?(updates, &match?(%Update{}, &1)),
         {:ok, actor} <- actor(scope) do
      approved_at = normalize_datetime(Keyword.get(opts, :at, DateTime.utc_now()))

      basis = %{
        organization_id: scope.organization_id,
        mission_id: mission_id,
        name: name,
        updates: updates,
        expected_result_sha256: Keyword.get(opts, :expected_result_sha256)
      }

      attrs = %{
        qualification_case_id:
          ContentHash.term_sha256({:mission_model_qualification_case, basis}),
        organization_id: scope.organization_id,
        mission_id: mission_id,
        name: name,
        status: :approved,
        input_term: :erlang.term_to_binary(updates, compressed: 6),
        expected_result_sha256: Keyword.get(opts, :expected_result_sha256),
        approved_by: actor,
        approved_at: approved_at,
        metadata: Keyword.get(opts, :metadata, %{})
      }

      case Repo.insert(QualificationCaseRow.changeset(attrs), on_conflict: :nothing) do
        {:ok, row} -> {:ok, case_document(row)}
        {:error, reason} -> {:error, reason}
      end
    else
      false -> {:error, :mission_model_qualification_inputs_required}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec run(binary(), binary(), binary(), binary(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def run(organization_id, mission_id, candidate_revision_id, binding_set_id, binding_set_version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(candidate_revision_id) and is_binary(binding_set_id) and
             is_integer(binding_set_version) and binding_set_version > 0 do
    with {:ok, %Revision{} = candidate} <-
           MissionModels.fetch_revision(organization_id, mission_id, candidate_revision_id),
         {:ok, candidate_plans} <-
           MissionModels.fetch_runtime_plans(organization_id, mission_id, candidate_revision_id),
         {:ok, baseline, baseline_plans} <- baseline(organization_id, mission_id, candidate),
         static <- static_comparison(baseline, candidate, baseline_plans, candidate_plans),
         replay <-
           replay_comparison(
             organization_id,
             mission_id,
             static.risk,
             baseline_plans,
             candidate_plans
           ),
         report <-
           build_report(
             mission_id,
             candidate,
             baseline,
             binding_set_id,
             binding_set_version,
             static,
             replay
           ) do
      persist_report(organization_id, report)
    end
  end

  @spec fetch(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def fetch(organization_id, mission_id, comparison_report_id) do
    case Repo.get_by(ComparisonReportRow,
           organization_id: organization_id,
           mission_id: mission_id,
           comparison_report_id: comparison_report_id
         ) do
      nil -> {:error, :mission_model_comparison_report_not_found}
      row -> {:ok, report_document(row)}
    end
  end

  defp baseline(organization_id, mission_id, candidate) do
    baseline_revision_id = active_revision_id(organization_id, mission_id)

    with {:ok, baseline} <-
           baseline_revision(organization_id, mission_id, candidate, baseline_revision_id) do
      baseline_plans(organization_id, mission_id, baseline)
    end
  end

  defp baseline_revision(organization_id, mission_id, candidate, baseline_revision_id) do
    if is_binary(baseline_revision_id) and baseline_revision_id != candidate.revision_id do
      MissionModels.fetch_revision(organization_id, mission_id, baseline_revision_id)
    else
      organization_id
      |> MissionModels.list_revisions(mission_id, status: :approved)
      |> Enum.find(&(&1.revision_id != candidate.revision_id))
      |> then(&{:ok, &1})
    end
  end

  defp baseline_plans(_organization_id, _mission_id, nil), do: {:ok, nil, %{}}

  defp baseline_plans(organization_id, mission_id, %Revision{} = baseline) do
    case MissionModels.fetch_runtime_plans(
           organization_id,
           mission_id,
           baseline.revision_id
         ) do
      {:ok, plans} -> {:ok, baseline, plans}
      {:error, reason} -> {:error, reason}
    end
  end

  defp active_revision_id(organization_id, mission_id) do
    case Activations.fetch_active_activation(organization_id, mission_id) do
      {:ok, activation} -> get_in(activation.metadata, ["mission_model", "revision_id"])
      {:error, :no_active_binding_set} -> nil
    end
  end

  defp static_comparison(baseline, candidate, baseline_plans, candidate_plans) do
    baseline_declarations = if baseline, do: baseline.declarations, else: %{}

    added = Map.keys(candidate.declarations) -- Map.keys(baseline_declarations)
    removed = Map.keys(baseline_declarations) -- Map.keys(candidate.declarations)

    changed =
      candidate.declarations
      |> Map.keys()
      |> Enum.filter(fn id ->
        Map.has_key?(baseline_declarations, id) and
          Declaration.fingerprint(candidate.declarations[id]) !=
            Declaration.fingerprint(baseline_declarations[id])
      end)

    affected = added ++ removed ++ changed

    kinds =
      affected
      |> Enum.flat_map(fn id ->
        [candidate.declarations[id], baseline_declarations[id]]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.kind)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      risk: risk(kinds),
      added: Enum.sort(added),
      removed: Enum.sort(removed),
      changed: Enum.sort(changed),
      affected_kinds: Enum.map(kinds, &Atom.to_string/1),
      changed_targets: changed_targets(baseline_plans, candidate_plans)
    }
  end

  defp risk(kinds) do
    cond do
      Enum.any?(kinds, &(&1 in @high_risk_kinds)) -> :high
      Enum.any?(kinds, &(&1 in @medium_risk_kinds)) -> :medium
      true -> :low
    end
  end

  defp changed_targets(baseline_plans, candidate_plans) do
    candidate_plans
    |> Enum.flat_map(fn {target, plan} ->
      case Map.get(baseline_plans, target) do
        %RuntimePlan{content_sha256: hash} when hash == plan.content_sha256 -> []
        _other -> [Atom.to_string(target)]
      end
    end)
    |> Enum.sort()
  end

  defp replay_comparison(_organization_id, _mission_id, risk, _baseline, _candidate)
       when risk in [:low, :medium] do
    %{required: false, status: :not_required, cases: []}
  end

  defp replay_comparison(organization_id, mission_id, :high, baseline_plans, candidate_plans) do
    cases = approved_cases(organization_id, mission_id)

    results =
      Enum.map(cases, fn qualification_case ->
        run_case(qualification_case, baseline_plans, candidate_plans)
      end)

    status =
      cond do
        cases == [] -> :failed
        Enum.all?(results, &(&1["status"] == "passed")) -> :passed
        true -> :failed
      end

    %{
      required: true,
      status: status,
      reason: if(cases == [], do: :qualification_corpus_required, else: nil),
      cases: results
    }
  end

  defp approved_cases(organization_id, mission_id) do
    QualificationCaseRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.status == :approved
    )
    |> order_by([row], asc: row.qualification_case_id)
    |> Repo.all()
  end

  defp run_case(row, baseline_plans, candidate_plans) do
    with {:ok, updates} <- decode_updates(row.input_term),
         {:ok, candidate_hash} <- execute(candidate_plans, updates),
         {:ok, expected_hash} <- expected_hash(row, baseline_plans, updates) do
      %{
        "qualification_case_id" => row.qualification_case_id,
        "name" => row.name,
        "status" => if(candidate_hash == expected_hash, do: "passed", else: "failed"),
        "expected_result_sha256" => expected_hash,
        "candidate_result_sha256" => candidate_hash
      }
    else
      {:error, reason} ->
        %{
          "qualification_case_id" => row.qualification_case_id,
          "name" => row.name,
          "status" => "failed",
          "reason" => inspect(reason)
        }
    end
  end

  defp expected_hash(row, baseline_plans, _updates) when map_size(baseline_plans) == 0 do
    case row.expected_result_sha256 do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :qualification_expected_result_required}
    end
  end

  defp expected_hash(_row, baseline_plans, updates), do: execute(baseline_plans, updates)

  defp execute(plans, updates) do
    with :ok <- PlanDecoder.validate(plans),
         {:ok, %Result{} = result, _state} <-
           SemanticRuntime.process(%State{}, updates, PlanDecoder.decode(plans)) do
      {:ok, semantic_result_sha256(result)}
    end
  end

  defp semantic_result_sha256(result) do
    ContentHash.term_sha256(%{
      updates:
        Enum.map(result.parameter_updates, fn update ->
          {update.parameter_id, update.value, update.quality, update.generation_time,
           update.receipt_time}
        end),
      monitoring:
        Enum.map(result.monitoring_results, fn monitoring ->
          {monitoring.policy_id, monitoring.parameter_id, monitoring.effective_state,
           monitoring.transition}
        end)
    })
  end

  defp decode_updates(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      updates when is_list(updates) -> {:ok, updates}
      _other -> {:error, :qualification_case_inputs_invalid}
    end
  rescue
    ArgumentError -> {:error, :qualification_case_inputs_invalid}
  end

  defp build_report(mission_id, candidate, baseline, binding_set_id, version, static, replay) do
    status = if replay.status in [:not_required, :passed], do: :passed, else: :failed

    report = %{
      "engine" => "mission_model_comparison_v1",
      "mission_id" => mission_id,
      "candidate_revision_id" => candidate.revision_id,
      "candidate_content_sha256" => candidate.content_sha256,
      "baseline_revision_id" => baseline && baseline.revision_id,
      "binding_set_id" => binding_set_id,
      "binding_set_version" => version,
      "status" => Atom.to_string(status),
      "risk" => Atom.to_string(static.risk),
      "static" => %{
        "added" => static.added,
        "removed" => static.removed,
        "changed" => static.changed,
        "affected_kinds" => static.affected_kinds,
        "changed_targets" => static.changed_targets
      },
      "replay" => %{
        "required" => replay.required,
        "status" => Atom.to_string(replay.status),
        "reason" =>
          case Map.get(replay, :reason) do
            nil -> nil
            reason -> Atom.to_string(reason)
          end,
        "cases" => replay.cases
      }
    }

    report_sha256 = ContentHash.term_sha256(report)

    report
    |> Map.put("report_sha256", report_sha256)
    |> Map.put(
      "comparison_report_id",
      ContentHash.term_sha256({:mission_model_comparison_report, report_sha256})
    )
  end

  defp persist_report(organization_id, report) do
    attrs = %{
      comparison_report_id: report["comparison_report_id"],
      organization_id: organization_id,
      mission_id: report["mission_id"],
      candidate_revision_id: report["candidate_revision_id"],
      baseline_revision_id: report["baseline_revision_id"],
      binding_set_id: report["binding_set_id"],
      binding_set_version: report["binding_set_version"],
      status: String.to_existing_atom(report["status"]),
      risk: String.to_existing_atom(report["risk"]),
      report_sha256: report["report_sha256"],
      report: report
    }

    case Repo.insert(ComparisonReportRow.changeset(attrs),
           on_conflict: :nothing,
           conflict_target: [
             :organization_id,
             :mission_id,
             :candidate_revision_id,
             :binding_set_id,
             :binding_set_version,
             :report_sha256
           ],
           returning: true
         ) do
      {:ok, %ComparisonReportRow{comparison_report_id: nil}} ->
        fetch_by_identity(attrs)

      {:ok, row} ->
        {:ok, report_document(row)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_by_identity(attrs) do
    row =
      Repo.get_by(ComparisonReportRow,
        organization_id: attrs.organization_id,
        mission_id: attrs.mission_id,
        candidate_revision_id: attrs.candidate_revision_id,
        binding_set_id: attrs.binding_set_id,
        binding_set_version: attrs.binding_set_version,
        report_sha256: attrs.report_sha256
      )

    if row, do: {:ok, report_document(row)}, else: {:error, :comparison_report_not_found}
  end

  defp report_document(row), do: JsonDocument.unwrap_value(row.report)

  defp case_document(row) do
    %{
      qualification_case_id: row.qualification_case_id,
      mission_id: row.mission_id,
      name: row.name,
      status: row.status,
      expected_result_sha256: row.expected_result_sha256,
      approved_at: row.approved_at
    }
  end

  defp actor(%Scope{actor_kind: :user, user: user}) when not is_nil(user) do
    {:ok, %{"kind" => "user", "id" => user.user_id, "display_name" => user.display_name}}
  end

  defp actor(%Scope{}), do: {:error, :human_qualification_approver_required}

  defp normalize_datetime(%DateTime{} = datetime) do
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
