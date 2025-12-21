defmodule Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository do
  @moduledoc """
  Ecto-based implementation of the ScheduleRepository port.

  This adapter provides persistence for schedules using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :schedule_repository, Cadence.Adapters.Persistence.Ecto.Schedules.EctoScheduleRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Schedules.ScheduleRepository.impl()
      {:ok, schedule} = repo.find(id, organization_id)
  """

  @behaviour Cadence.Ports.Repository.Schedules.ScheduleRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Schedules.Schedule

  # ===========================================================================
  # ScheduleRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, organization_id) do
    query =
      from s in Schedule,
        where: s.id == ^id and s.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schedule -> {:ok, Repo.preload(schedule, :procedure)}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Repo.get(Schedule, id) do
      nil -> {:error, :not_found}
      schedule -> {:ok, Repo.preload(schedule, :procedure)}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from s in Schedule,
        where: s.organization_id == ^organization_id,
        order_by: [asc: s.name]

    query = apply_filters(query, mission_id: mission_id, procedure_id: procedure_id, enabled_only: enabled_only)
    query = if limit, do: from(s in query, limit: ^limit, offset: ^offset), else: query

    query
    |> Repo.all()
    |> Repo.preload(:procedure)
  end

  @impl true
  def list_enabled_cron do
    Schedule
    |> where([s], s.enabled == true)
    |> where([s], s.schedule_type == :cron)
    |> where([s], not is_nil(s.cron_expression))
    |> Repo.all()
    |> Enum.map(&schedule_to_cron_job/1)
  end

  @impl true
  def list_due_once do
    now = DateTime.utc_now()

    Schedule
    |> where([s], s.enabled == true)
    |> where([s], s.schedule_type == :once)
    |> where([s], s.scheduled_at <= ^now)
    |> where([s], is_nil(s.last_run_at))
    |> Repo.all()
    |> Repo.preload(:procedure)
  end

  @impl true
  def save(%Schedule{id: nil} = schedule) do
    %Schedule{}
    |> Schedule.changeset(Map.from_struct(schedule))
    |> Repo.insert()
    |> case do
      {:ok, schedule} -> {:ok, Repo.preload(schedule, :procedure)}
      error -> error
    end
  end

  def save(%Schedule{} = schedule) do
    schedule
    |> Schedule.changeset(Map.from_struct(schedule))
    |> Repo.update()
    |> case do
      {:ok, schedule} -> {:ok, Repo.preload(schedule, :procedure)}
      error -> error
    end
  end

  @impl true
  def delete(%Schedule{} = schedule) do
    case Repo.delete(schedule) do
      {:ok, deleted} -> {:ok, deleted}
      {:error, changeset} -> {:error, extract_errors(changeset)}
    end
  end

  @impl true
  def record_run(%Schedule{} = schedule, next_run_at \\ nil) do
    schedule
    |> Schedule.run_changeset(%{
      last_run_at: DateTime.utc_now(),
      next_run_at: next_run_at,
      run_count: (schedule.run_count || 0) + 1
    })
    |> Repo.update()
  end

  @impl true
  def enable(%Schedule{} = schedule) do
    schedule
    |> Schedule.changeset(%{enabled: true})
    |> Repo.update()
    |> case do
      {:ok, schedule} -> {:ok, Repo.preload(schedule, :procedure)}
      error -> error
    end
  end

  @impl true
  def disable(%Schedule{} = schedule) do
    schedule
    |> Schedule.changeset(%{enabled: false})
    |> Repo.update()
    |> case do
      {:ok, schedule} -> {:ok, Repo.preload(schedule, :procedure)}
      error -> error
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:mission_id, nil}, q ->
        q

      {:mission_id, mission_id}, q ->
        from(s in q, where: s.mission_id == ^mission_id or is_nil(s.mission_id))

      {:procedure_id, nil}, q ->
        q

      {:procedure_id, procedure_id}, q ->
        from(s in q, where: s.procedure_id == ^procedure_id)

      {:enabled_only, false}, q ->
        q

      {:enabled_only, true}, q ->
        from(s in q, where: s.enabled == true)
    end)
  end

  defp schedule_to_cron_job(%Schedule{} = schedule) do
    {schedule.cron_expression,
     {Cadence.Schedules.Workers.ExecuteScheduleWorker,
      [schedule_id: schedule.id, name: "schedule:#{schedule.id}"]}}
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    {:validation,
     Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
       Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
         opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
       end)
     end)}
  end
end
