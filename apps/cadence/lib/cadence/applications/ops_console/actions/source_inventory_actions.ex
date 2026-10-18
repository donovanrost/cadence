defmodule Cadence.Applications.OpsConsole.Actions.SourceInventoryActions do
  @moduledoc "Native source actions bound to reviewed source, binding and deployment identities."
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.DataSources, as: Adapter
  alias Cadence.DataSources.AdapterRegistry
  alias Cadence.Jobs
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.Sources, as: Read
  alias Cadence.Reads.DataSources

  @source_actions ~w(disable-source enable-source reconcile-tsdb-backend deprovision-tsdb-backend provision-tsdb-backend probe-source rotate-source-credential)
  @lifecycle_actions ~w(reconcile-tsdb-backend deprovision-tsdb-backend provision-tsdb-backend)
  @job_actions ~w(retry-deployment-run requeue-deployment-run)
  @actions ~w(read-page validate-registration register-source change-binding) ++
             @source_actions ++ @job_actions
  def actions, do: @actions

  def admit_input("read-page", %{"query" => query} = input) when map_size(input) == 1 do
    case Read.admit_query(query) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_query}
    end
  end

  def admit_input(
        action,
        %{"params" => params, "review" => review, "confirmed" => confirmed} = input
      )
      when map_size(input) == 3 and is_map(params) and is_map(review) and is_boolean(confirmed) do
    validation_action = if action == "validate-registration", do: "register-source", else: action

    with true <- action in @actions,
         true <- bounded_params?(params),
         true <- Enum.all?(review, fn {key, value} -> is_binary(key) and hash?(value) end),
         true <- Enum.sort(Map.keys(review)) == Enum.sort(review_keys(action)),
         {:ok, _} <- Adapter.validate_input(validation_action, params) do
      :ok
    else
      _ -> {:error, :invalid_source_input}
    end
  end

  def admit_input(_, _), do: {:error, :invalid_source_input}

  def execute(scope, mission, mode, capture, action, input, operation_id) do
    with :ok <- admit_input(action, input),
         true <- is_binary(operation_id) and byte_size(operation_id) in 1..240,
         {:ok, fresh, _} <- Read.load(scope, mission, mode, query(capture.model.query)) do
      dispatch(scope, mission, mode, capture.model, fresh, action, input, operation_id)
    else
      _ -> {:rejected, ["invalid_or_unavailable"]}
    end
  end

  defp dispatch(scope, mission, mode, _captured, _fresh, "read-page", input, _id) do
    case Read.load(scope, mission, mode, input["query"]) do
      {:ok, model, review} -> {:page, model, review, input["query"]}
      _ -> {:rejected, ["read_unavailable"]}
    end
  end

  defp dispatch(scope, mission, "registration", _captured, _fresh, action, input, id)
       when action in ["validate-registration", "register-source"] do
    case registration_ready(scope, mission, input["params"]) do
      :ok ->
        registration_result(scope, mission, action, input, id)

      _ ->
        if action == "validate-registration",
          do: {:ok, %{valid: false, feedback: ["source_or_credentials_unavailable"]}},
          else: {:rejected, ["source_or_credentials_unavailable"]}
    end
  end

  defp dispatch(scope, mission, "settings", captured, fresh, action, input, id) do
    with true <- input["confirmed"],
         :ok <- reviewed_source(captured, fresh, input["review"]),
         true <- fresh.selected.source.editable,
         :ok <- reviewed_subject(scope, mission, captured, fresh, action, input) do
      perform(
        scope,
        mission,
        "data_source_settings",
        action,
        input["params"],
        id,
        fresh.selected.source.id
      )
    else
      _ -> {:rejected, ["review_changed_or_unavailable"]}
    end
  end

  defp dispatch(_, _, _, _, _, _, _, _), do: {:rejected, ["forbidden"]}

  defp registration_result(_scope, _mission, "validate-registration", _input, _id),
    do: {:ok, %{valid: true, feedback: []}}

  defp registration_result(scope, mission, "register-source", %{"confirmed" => true} = input, id),
    do:
      perform(
        scope,
        mission,
        "data_source_registration",
        "register-source",
        input["params"],
        id,
        String.trim(input["params"]["source"]["data_source_id"])
      )

  defp registration_result(_, _, _, _, _), do: {:rejected, ["confirmation_required"]}

  defp registration_ready(scope, mission, params) do
    {:ok, %{source: attrs}} = Adapter.validate_input("register-source", params)

    with :ok <- Adapter.validate_registration(scope.organization_id, mission, params),
         {:error, :data_source_not_found} <- DataSources.fetch_data_source(attrs.data_source_id),
         :ok <- available_credential(scope, mission, attrs) do
      :ok
    else
      _ -> {:error, :source_or_credentials_unavailable}
    end
  end

  defp available_credential(_, _, %{credentials_ref: nil}), do: :ok

  defp available_credential(scope, mission, attrs) do
    case DataSources.fetch_credential_reference(attrs.credentials_ref) do
      {:error, :credential_reference_not_found} ->
        :ok

      {:ok, ref} ->
        if ref.organization_id == scope.organization_id and ref.mission_id == mission and
             ref.data_source_id == attrs.data_source_id and ref.status == :active,
           do: :ok,
           else: {:error, :credential_unavailable}
    end
  end

  defp reviewed_source(%{selected: %{source: captured}}, %{selected: %{source: fresh}}, %{
         "source" => evidence
       }) do
    if captured.id == fresh.id and captured.evidence == evidence and fresh.evidence == evidence,
      do: :ok,
      else: {:error, :source_changed}
  end

  defp reviewed_source(_, _, _), do: {:error, :source_unavailable}

  defp reviewed_subject(_scope, _mission, _captured, fresh, action, input)
       when action in @source_actions do
    params = input["params"]
    source = fresh.selected.source

    if (action not in @lifecycle_actions or dedicated_backend?(source)) and
         params["data-source-id"] == source.id and
         (action != "rotate-source-credential" or
            params["credentials-ref"] == source.credential_reference),
       do: :ok,
       else: {:error, :source_mismatch}
  end

  defp reviewed_subject(scope, mission, captured, fresh, "change-binding", input) do
    params = input["params"]["binding"]
    expected = input["review"]

    with old when not is_nil(old) <-
           Enum.find(captured.bindings.entries, &(&1.id == params["binding_id"])),
         true <- old.evidence == expected["binding"],
         {:ok, binding} <- DataSources.fetch_data_binding(old.id),
         true <-
           Read.editable?(binding, scope, mission) and
             binding.data_source_id == fresh.selected.source.id,
         true <- Read.binding_evidence(binding) == expected["binding"],
         target when not is_nil(target) <-
           Enum.find(captured.sources.entries, &(&1.id == params["data_source_id"])),
         true <- target.evidence == expected["target_source"],
         {:ok, source} <- DataSources.fetch_data_source(target.id),
         true <- Read.visible?(source, scope, mission) and source.status == :active,
         true <- Read.source_evidence(source) == expected["target_source"],
         true <- AdapterRegistry.logical_source(source.adapter) == binding.logical_source do
      :ok
    else
      _ -> {:error, :binding_changed}
    end
  end

  defp reviewed_subject(scope, mission, captured, fresh, action, input)
       when action in @job_actions do
    with old when not is_nil(old) <-
           Enum.find(captured.selected.jobs.entries, &(&1.id == input["params"]["job-id"])),
         true <- old.evidence == input["review"]["job"],
         current when not is_nil(current) <-
           Enum.find(fresh.selected.jobs.entries, &(&1.id == old.id)),
         true <- current.evidence == old.evidence,
         {:ok, job} <- Jobs.fetch_job(old.id),
         true <-
           job.mission_id == mission and
             job.job_type in [:tsdb_backend_lifecycle, :managed_questdb_provisioning],
         true <- job.status == expected_job_status(action),
         true <- payload(job, "data_source_id") == fresh.selected.source.id,
         true <- payload(job, "organization_id") in [nil, scope.organization_id],
         true <- payload(job, "mission_id") in [nil, mission],
         true <- Read.job_evidence(job) == old.evidence do
      :ok
    else
      _ -> {:error, :job_changed}
    end
  end

  defp reviewed_subject(_, _, _, _, _, _), do: {:error, :unsupported_action}

  defp dedicated_backend?(source),
    do: source.kind == "byo_tsdb" and source.isolation in ["org_isolated", "mission_isolated"]

  defp expected_job_status("retry-deployment-run"), do: :failed
  defp expected_job_status("requeue-deployment-run"), do: :running

  defp perform(scope, mission, surface, action, params, id, source_id) do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface,
      surface_version: 1,
      action_id: action,
      params: params,
      idempotency_key: id
    }

    case Adapter.execute(scope, HostContext.mission(mission), surface, request) do
      {:ok, value} ->
        {:ok,
         %{
           contract_version: 1,
           organization_id: scope.organization_id,
           mission_id: mission,
           actor_id: actor_id(scope),
           action: action,
           operation_id: id,
           source_id: source_id,
           result: Adapter.result(value),
           event_ids: event_ids(value)
         }}

      _ ->
        {:unconfirmed, %{source_id: source_id, operation_id: id}}
    end
  end

  defp event_ids(%{current_event_id: id}) when is_binary(id), do: [id]
  defp event_ids(%{source: source}), do: event_ids(source)
  defp event_ids(%{event: event}), do: event_ids(event)
  defp event_ids(%{source_health_event_id: id}), do: [id]
  defp event_ids(%{source_credential_event_id: id}), do: [id]
  defp event_ids(_), do: []
  defp payload(job, key), do: Map.get(job.payload, key)
  defp review_keys(action) when action in ["register-source", "validate-registration"], do: []
  defp review_keys("change-binding"), do: ~w(source binding target_source)
  defp review_keys(action) when action in @job_actions, do: ~w(source job)
  defp review_keys(_), do: ~w(source)

  defp bounded_params?(params) when is_map(params),
    do:
      map_size(params) <= 10 and
        Enum.all?(params, fn {key, value} ->
          is_binary(key) and byte_size(key) <= 80 and bounded_field?(key, value)
        end)

  defp bounded_params?(value) when is_binary(value),
    do: String.valid?(value) and byte_size(value) <= 240

  defp bounded_params?(_), do: false

  defp bounded_field?("endpoint_ref", value) when is_binary(value),
    do: String.valid?(value) and byte_size(value) <= 2_048

  defp bounded_field?(_, value), do: bounded_params?(value)
  defp actor_id(%{user: %{user_id: id}}), do: id
  defp actor_id(%{service_identity: %{service_identity_id: id}}), do: id
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/^[a-f0-9]{64}$/, value)
  defp query(query), do: Map.new(query, fn {key, value} -> {to_string(key), value} end)
end
