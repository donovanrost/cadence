defmodule Cadence.Applications.OpsConsole.Actions.HistoricalWorkflowActions do
  @moduledoc "Native historical-workflow input, reviewed decisions and actual result identities."

  alias Cadence.Applications.OpsConsole.Actions.HistoricalWorkflowRequest
  alias Cadence.Auth.Policy
  alias Cadence.Control.TelemetryDataManagement, as: Commands
  alias Cadence.Jobs
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.HistoricalWorkflows, as: Read
  alias Cadence.Reads.Telemetry
  alias Cadence.Telemetry.DataManagement.{WorkflowEventEvidence, WorkflowLock}

  @actions ~w(read-page validate-request record-request transition-group retry-group request-correction)
  @fields ~w(workflow run_id realm data_source_id source_binding_id point_ids source_from source_to reason confirmed)
  @stages ~w(approved rejected started completed failed)
  def actions, do: @actions
  def admit_input(action, input), do: admit(action, input)

  def execute(scope, mission, mode, capture, action, input, operation_id) do
    with true <- action in @actions,
         true <- text?(operation_id, 240) and operation_id != "",
         {:ok, _model, _review} <- Read.load(scope, mission, mode, %{}),
         :ok <- admit(action, input) do
      dispatch(scope, mission, mode, capture, action, input, operation_id)
    else
      _ -> {:rejected, ["invalid_or_unavailable"]}
    end
  end

  defp admit("read-page", %{"query" => query} = input) when map_size(input) == 1 do
    case Read.admit_query(query) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_query}
    end
  end

  defp admit(action, %{"request" => values, "binding_evidence" => evidence} = input)
       when action in ["validate-request", "record-request"] and map_size(input) == 2 and
              is_map(values) do
    if Enum.sort(Map.keys(values)) == Enum.sort(@fields) and
         Enum.all?(Map.values(values), &text?(&1, 8_192)) and text?(evidence, 64) and
         text?(values["run_id"], 232), do: :ok, else: {:error, :invalid_request}
  end

  defp admit(action, input) when is_map(input) do
    extra =
      case action do
        "transition-group" -> ["stage"]
        "request-correction" -> ["event_id"]
        "retry-group" -> []
        _ -> ["unsupported"]
      end

    keys = ~w(group_id evidence reason confirmed) ++ extra

    if Enum.sort(Map.keys(input)) == Enum.sort(keys) and decision_values?(action, input),
      do: :ok,
      else: {:error, :invalid_decision}
  end

  defp admit(_, _), do: {:error, :invalid_input}

  defp decision_values?(action, input) do
    input["confirmed"] == true and text?(input["reason"], 4_096) and
      String.trim(input["reason"]) != "" and decision_identities?(input) and
      (action != "transition-group" or input["stage"] in @stages)
  end

  defp decision_identities?(input),
    do:
      Enum.all?(Map.drop(input, ["reason", "confirmed"]), fn {_, value} ->
        text?(value, 240) and value != ""
      end)

  defp dispatch(scope, mission, mode, capture, "read-page", input, _id) do
    case Read.load(scope, mission, mode, input["query"], capture.model.defaults) do
      {:ok, model, review} -> {:page, model, review, input["query"]}
      _ -> {:rejected, ["read_unavailable"]}
    end
  end

  defp dispatch(scope, mission, mode, capture, "validate-request", input, _id) do
    case prepare_request(scope, mission, mode, capture, input) do
      {:ok, _} -> {:ok, %{valid: true, feedback: []}}
      {:error, feedback} -> {:ok, %{valid: false, feedback: feedback}}
    end
  end

  defp dispatch(scope, mission, mode, capture, "record-request", input, id) do
    values = input["request"]

    group =
      if String.trim(values["run_id"]) == "",
        do: "historical-" <> id,
        else: String.trim(values["run_id"])

    if values["confirmed"] == "true" do
      locked(scope, mission, group, fn ->
        request_effect(scope, mission, mode, capture, input, group, id)
      end)
    else
      {:rejected, ["confirmation_required"]}
    end
  end

  defp dispatch(scope, mission, mode, capture, action, input, id) do
    with :ok <-
           Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}),
         true <- mode == "manage" do
      locked(scope, mission, input["group_id"], fn ->
        reviewed_effect(scope, mission, capture, action, input, id)
      end)
    else
      _ -> {:rejected, ["forbidden"]}
    end
  end

  defp request_effect(scope, mission, mode, capture, input, group, id) do
    with {:ok, request} <- prepare_request(scope, mission, mode, capture, input),
         :ok <- unused_request(scope, mission, group, request.point_ids) do
      attrs =
        request.attrs
        |> Map.put(:backfill_run_id, group)
        |> Map.put(:import_run_id, group)
        |> Map.put(:payload, %{"host_operation_id" => id})

      result =
        Commands.record_historical_data_workflow_request(
          request.workflow,
          attrs,
          request.point_ids,
          []
        )

      result(scope, mission, group, id, "record-request", result)
    else
      _ -> {:rejected, ["request_changed_or_exists"]}
    end
  end

  defp reviewed_effect(scope, mission, capture, action, input, id) do
    with %{selected: %{id: group, evidence: evidence}} <- capture.model,
         true <- group == input["group_id"] and evidence == input["evidence"],
         {:ok, review} <- Read.group_review(scope, mission, group),
         true <- review.evidence == evidence and review.workflow in ["backfill", "import"] do
      attrs = actor_attrs(scope, mission, input["reason"], id)
      effect(scope, mission, group, id, action, input, review, attrs)
    else
      _ -> {:rejected, ["review_changed"]}
    end
  end

  defp prepare_request(scope, mission, mode, capture, input) do
    with {:ok, request} <- HistoricalWorkflowRequest.validate(scope, mission, input["request"]),
         {:ok, _, fresh} <- Read.load(scope, mission, mode, %{}),
         binding = input["request"]["source_binding_id"],
         evidence when is_binary(evidence) <- capture.review.bindings[binding],
         true <- evidence == input["binding_evidence"] and evidence == fresh.bindings[binding] do
      {:ok, request}
    else
      {:error, feedback} when is_list(feedback) -> {:error, feedback}
      _ -> {:error, [%{field: "source_binding_id", code: "review_changed"}]}
    end
  end

  defp unused_request(scope, mission, group, points) do
    count = max(length(points), 1)

    runs =
      for index <- 1..count,
          do:
            if(count == 1,
              do: group,
              else: group <> "-" <> String.pad_leading(to_string(index), 3, "0")
            )

    with {:error, {:request_group_not_found, ^group}} <-
           Telemetry.fetch_backfill_lifecycle_group_events(mission, group,
             organization_id: scope.organization_id
           ),
         true <-
           Enum.all?(runs, fn run ->
             match?({:error, _}, Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run)) and
               Telemetry.list_backfill_lifecycle_events(mission,
                 organization_id: scope.organization_id,
                 backfill_run_id: run,
                 limit: 1
               ) == []
           end),
         do: :ok,
         else: (_ -> {:error, :run_exists})
  end

  defp effect(scope, mission, group, id, "transition-group" = action, input, review, attrs) do
    result(
      scope,
      mission,
      group,
      id,
      action,
      Commands.record_historical_data_workflow_group_transition(
        review.workflow,
        input["stage"],
        group,
        attrs,
        []
      )
    )
  end

  defp effect(scope, mission, group, id, "retry-group" = action, _input, _review, attrs) do
    result(
      scope,
      mission,
      group,
      id,
      action,
      Commands.retry_historical_data_workflow_group_failed_jobs(group, attrs, [])
    )
  end

  defp effect(scope, mission, group, id, "request-correction" = action, input, review, attrs) do
    case Enum.find(review.events, &(&1.backfill_lifecycle_event_id == input["event_id"])) do
      nil ->
        {:rejected, ["review_changed"]}

      event ->
        attrs =
          Map.merge(attrs, %{
            backfill_run_id: "historical-correction-" <> id,
            import_run_id: "historical-correction-" <> id
          })

        result(
          scope,
          mission,
          group,
          id,
          action,
          Commands.record_historical_data_workflow_correction_request(
            review.workflow,
            attrs,
            %{
              "request_group_id" => group,
              "original_event_id" => event.backfill_lifecycle_event_id,
              "original_run_id" => event.backfill_run_id,
              "original_job_id" => WorkflowEventEvidence.job_id(event)
            },
            []
          )
        )
    end
  end

  defp result(scope, mission, group, id, action, {:ok, events, jobs})
       when is_list(events) and is_list(jobs) do
    job_ids = for {:ok, %{job_id: job_id}} <- jobs, do: job_id

    if Enum.all?(jobs, &match?({:ok, _}, &1)),
      do: {:ok, receipt(scope, mission, group, id, action, events, job_ids)},
      else: {:unconfirmed, receipt(scope, mission, group, id, action, events, job_ids)}
  end

  defp result(
         scope,
         mission,
         group,
         id,
         action,
         {:ok, %{events: events, failed: failed} = summary}
       ) do
    job_ids = Enum.map(events, & &1.payload["retry_job_id"]) |> Enum.filter(&is_binary/1)

    result =
      receipt(scope, mission, group, id, action, events, job_ids)
      |> Map.put(:retry_counts, Map.take(summary, [:retried, :skipped, :nonretryable, :failed]))

    {if(failed == 0, do: :ok, else: :unconfirmed), result}
  end

  defp result(scope, mission, group, id, action, {:ok, events}) when is_list(events),
    do: {:ok, receipt(scope, mission, group, id, action, events)}

  defp result(scope, mission, group, id, action, {:ok, event}),
    do: {:ok, receipt(scope, mission, group, id, action, [event])}

  defp result(_scope, _mission, group, id, _action, _),
    do: {:unconfirmed, %{group_id: group, operation_id: id}}

  defp receipt(scope, mission, group, id, action, events, jobs \\ []) do
    ids = Enum.map(events, & &1.backfill_lifecycle_event_id)

    %{
      contract_version: 1,
      organization_id: scope.organization_id,
      mission_id: mission,
      actor_id: scope.user.user_id,
      action: action,
      operation_id: id,
      group_id: group,
      event_ids: Enum.take(ids, 25),
      job_ids: Enum.take(jobs, 25),
      job_count: length(jobs),
      job_ids_truncated: length(jobs) > 25,
      event_count: length(ids),
      event_ids_truncated: length(ids) > 25,
      event_digest: :crypto.hash(:sha256, Jason.encode!(ids)) |> Base.encode16(case: :lower)
    }
  end

  defp actor_attrs(scope, mission, reason, id),
    do: %{
      organization_id: scope.organization_id,
      mission_id: mission,
      actor_id: scope.user.user_id,
      actor_kind: "operator",
      reason: reason,
      payload: %{"host_operation_id" => id}
    }

  defp locked(scope, mission, group, callback) do
    case WorkflowLock.with_group(scope.organization_id, mission, group, callback) do
      {:error, :historical_workflow_group_busy} -> {:rejected, ["operation_busy"]}
      other -> other
    end
  end

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value)
end
