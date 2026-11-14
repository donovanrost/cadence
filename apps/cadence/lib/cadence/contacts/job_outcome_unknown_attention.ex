defmodule Cadence.Contacts.JobOutcomeUnknownAttention do
  @moduledoc """
  The `job_outcome_unknown` source of the mission attention read (ux U54): Cadence stopped while
  a job that isn't safe to run again was running, so nobody knows whether it finished. Cadence
  won't run it again by itself; an operator checks, then retries it or closes the item.

  One item per run (`job_outcome_unknown:<job_id>:<attempt>`; Jobs.OutcomeResolutions). P2,
  P1 when the job's pass starts within 2 h or is live (the default rule over `starts_at`). Retry
  and close are operator actions, audited in the item's resolution (actor, time, note).
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{JobOutcomeWords, ProviderReservations, ScheduleOperation}
  alias Cadence.GroundNetworks.MissionProviders
  alias Cadence.Jobs.{Job, OutcomeResolutions}
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @source "job_outcome_unknown"
  @conflict "outcome_unknown"

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    case OutcomeResolutions.open_jobs(mission) do
      [] ->
        []

      jobs ->
        providers = providers(org, mission)
        Enum.map(jobs, &item(&1, org, mission, providers))
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(_org, mission),
    do: %{open: length(OutcomeResolutions.open_jobs(mission)), acknowledged: 0}

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(_org, mission, %DateTime{} = since) do
    for row <- OutcomeResolutions.resolutions_since(mission, since) do
      %{
        id: row.item_id,
        source: @source,
        conflict: @conflict,
        resolved_by: row.actor,
        action: row.action,
        resolved_at: row.resolved_at,
        note: row.note
      }
    end
  end

  @doc "Not an action for this source: retry or close is the answer (ux U54)."
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:error, :attention_item_not_open}
  def acknowledge(_scope, _mission, _id), do: {:error, :attention_item_not_open}

  @doc "Close without retry: the job stays as it is. The note is required (for the audit)."
  @spec resolve(Scope.t(), binary(), binary(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def resolve(%Scope{} = scope, mission, id, action_text) do
    note = String.trim(action_text || "")

    with {:ok, actor} <- actor(scope, mission),
         :ok <- if(note == "", do: {:error, :reason_required}, else: :ok),
         {:ok, job} <- OutcomeResolutions.fetch_open(mission, id),
         {:ok, row} <- OutcomeResolutions.decide(job, :closed, actor, note) do
      decided(scope, mission, job, row)
    end
  end

  @doc """
  Retry: the job goes back in the queue, the only way it runs again. `confirmed` must be true
  (the operator checked that it didn't happen).
  """
  @spec retry(Scope.t(), binary(), binary(), boolean(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def retry(%Scope{} = scope, mission, id, confirmed, note) do
    note = if is_binary(note) and String.trim(note) != "", do: String.trim(note)

    with {:ok, actor} <- actor(scope, mission),
         :ok <- if(confirmed == true, do: :ok, else: {:error, :confirmation_required}),
         {:ok, job} <- OutcomeResolutions.fetch_open(mission, id),
         {:ok, row} <- OutcomeResolutions.decide(job, :retried, actor, note) do
      decided(scope, mission, job, row)
    end
  end

  defp decided(scope, mission, job, row) do
    ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)
    item = item(job, scope.organization_id, mission, providers(scope.organization_id, mission))

    {:ok,
     %{
       item
       | state: "resolved",
         actions: [],
         resolution: %{
           action: row.action,
           actor: row.actor,
           at: row.resolved_at,
           note: row.note,
           provider_reference: nil
         }
     }}
  end

  defp item(%Job{} = job, org, mission, providers) do
    {context, reservation} = context(job, org, mission, providers)

    %{
      id: OutcomeResolutions.item_id(job),
      source: @source,
      conflict: @conflict,
      state: "open",
      raised_at: job.completed_at,
      acknowledged_by: nil,
      resolution: nil,
      job: %{
        id: job.job_id,
        type_key: Atom.to_string(job.job_type),
        run_id: job.run_id,
        attempt: job.attempt_count,
        node: nil
      },
      words: JobOutcomeWords.words(job.job_type, context),
      started_at: job.started_at,
      found_at: job.completed_at,
      actions: ["retry", "close"]
    }
    |> Map.merge(pass(reservation))
  end

  # What the words and the pass fields come from: a booking's operation and its reservation;
  # a TSDB run's payload. Anything missing just falls back to the type's noun.
  defp context(%Job{job_type: :contact_schedule_operation} = job, org, mission, providers) do
    case schedule_operation(job.run_id) do
      %ScheduleOperation{} = operation ->
        reservation = reservation(org, mission, operation.reservation_id)

        provider_id =
          (reservation && reservation.provider_id) ||
            get_in(operation.input || %{}, ["provider_id"])

        {%{action: operation.action, provider_name: get_in(providers, [provider_id])},
         reservation}

      nil ->
        {%{}, nil}
    end
  end

  defp context(%Job{payload: payload}, _org, _mission, _providers) when is_map(payload) do
    attrs = if is_map(payload["attrs"]), do: payload["attrs"], else: %{}

    {%{
       operation: text(payload["operation"]),
       source_name: text(payload["display_name"] || payload["data_source_name"]),
       artifact_name: text(payload["artifact_name"]),
       workflow: text(payload["workflow"]),
       definition_name: text(payload["definition_name"]),
       definition_count: payload["definition_count"],
       span_from: text(payload["span_from"] || attrs["receipt_from"]),
       span_to: text(payload["span_to"] || attrs["receipt_to"])
     }, nil}
  end

  defp context(_job, _org, _mission, _providers), do: {%{}, nil}

  defp schedule_operation(run_id) when is_binary(run_id) do
    case Ecto.UUID.cast(run_id) do
      {:ok, id} -> Repo.get(ScheduleOperation, id)
      :error -> nil
    end
  end

  defp schedule_operation(_run_id), do: nil

  defp reservation(org, mission, id) when is_binary(id) do
    case ProviderReservations.fetch(org, mission, id) do
      {:ok, reservation} -> reservation
      _missing -> nil
    end
  end

  defp reservation(_org, _mission, _id), do: nil

  defp pass(nil) do
    %{
      realized_contact_id: nil,
      contact_id: nil,
      spacecraft_id: nil,
      provider_reservation_id: nil,
      ground_station_ref: nil,
      provider_id: nil,
      starts_at: nil,
      ends_at: nil
    }
  end

  defp pass(reservation) do
    %{
      realized_contact_id: nil,
      contact_id: reservation.scheduled_contact_id,
      spacecraft_id: reservation.spacecraft_id,
      provider_reservation_id: reservation.provider_reservation_id,
      ground_station_ref:
        Enum.find_value(
          [reservation.provider_confirmed_snapshot_document, reservation.request_document],
          &(is_map(&1) && &1["ground_station_ref"])
        ),
      provider_id: reservation.provider_id,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at
    }
  end

  defp providers(org, mission) do
    org
    |> MissionProviders.list_providers(mission)
    |> Map.new(&{&1.provider_id, &1.display_name})
  end

  # todo(authz): Cedar should decide who may retry or close an unknown-outcome job (any mission
  # operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil
end
