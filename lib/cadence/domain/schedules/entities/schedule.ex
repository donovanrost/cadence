defmodule Cadence.Domain.Schedules.Entities.Schedule do
  @moduledoc """
  Domain entity representing a scheduled procedure execution.

  Schedules define when procedures should be automatically executed.
  They support cron expressions for recurring schedules or one-time
  execution at a specific datetime.

  This is a pure domain entity with no Ecto dependencies.
  """

  @type schedule_type :: :cron | :once

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          description: String.t() | nil,
          enabled: boolean(),
          schedule_type: schedule_type(),
          cron_expression: String.t() | nil,
          scheduled_at: DateTime.t() | nil,
          timezone: String.t(),
          parameters: map(),
          last_run_at: DateTime.t() | nil,
          next_run_at: DateTime.t() | nil,
          run_count: non_neg_integer(),
          procedure_id: String.t(),
          organization_id: String.t(),
          mission_id: String.t() | nil,
          target_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:name, :schedule_type, :procedure_id, :organization_id]
  defstruct [
    :id,
    :name,
    :description,
    :cron_expression,
    :scheduled_at,
    :last_run_at,
    :next_run_at,
    :procedure_id,
    :organization_id,
    :mission_id,
    :target_id,
    :inserted_at,
    :updated_at,
    enabled: true,
    schedule_type: :cron,
    timezone: "UTC",
    parameters: %{},
    run_count: 0
  ]

  @schedule_types [:cron, :once]

  @doc """
  Creates a new schedule entity.

  ## Parameters

  - `attrs` - Map with required keys: `:name`, `:schedule_type`, `:procedure_id`, `:organization_id`

  ## Returns

  - `{:ok, schedule}` - Valid schedule created
  - `{:error, reason}` - Validation error
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    with {:ok, name} <- validate_required(attrs, :name),
         {:ok, schedule_type} <- validate_schedule_type(attrs),
         {:ok, procedure_id} <- validate_required(attrs, :procedure_id),
         {:ok, organization_id} <- validate_required(attrs, :organization_id),
         :ok <- validate_schedule_timing(schedule_type, attrs),
         :ok <- validate_cron_expression(attrs) do
      {:ok,
       %__MODULE__{
         id: Map.get(attrs, :id),
         name: name,
         description: Map.get(attrs, :description),
         enabled: Map.get(attrs, :enabled, true),
         schedule_type: schedule_type,
         cron_expression: Map.get(attrs, :cron_expression),
         scheduled_at: Map.get(attrs, :scheduled_at),
         timezone: Map.get(attrs, :timezone, "UTC"),
         parameters: Map.get(attrs, :parameters, %{}),
         last_run_at: Map.get(attrs, :last_run_at),
         next_run_at: Map.get(attrs, :next_run_at),
         run_count: Map.get(attrs, :run_count, 0),
         procedure_id: procedure_id,
         organization_id: organization_id,
         mission_id: Map.get(attrs, :mission_id),
         target_id: Map.get(attrs, :target_id),
         inserted_at: Map.get(attrs, :inserted_at),
         updated_at: Map.get(attrs, :updated_at)
       }}
    end
  end

  @doc """
  Enables the schedule.
  """
  @spec enable(t()) :: {:ok, t()}
  def enable(%__MODULE__{} = schedule) do
    {:ok, %{schedule | enabled: true}}
  end

  @doc """
  Disables the schedule.
  """
  @spec disable(t()) :: {:ok, t()}
  def disable(%__MODULE__{} = schedule) do
    {:ok, %{schedule | enabled: false}}
  end

  @doc """
  Records that the schedule was run.

  Increments run_count and updates last_run_at.
  """
  @spec record_run(t(), DateTime.t() | nil) :: {:ok, t()}
  def record_run(%__MODULE__{} = schedule, next_run_at \\ nil) do
    {:ok,
     %{
       schedule
       | last_run_at: DateTime.utc_now(),
         next_run_at: next_run_at,
         run_count: schedule.run_count + 1
     }}
  end

  @doc """
  Updates the next run time.
  """
  @spec update_next_run(t(), DateTime.t() | nil) :: {:ok, t()}
  def update_next_run(%__MODULE__{} = schedule, next_run_at) do
    {:ok, %{schedule | next_run_at: next_run_at}}
  end

  @doc """
  Updates the schedule with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = schedule, attrs) do
    {:ok, schedule}
    |> maybe_update_name(attrs)
    |> maybe_update_description(attrs)
    |> maybe_update_enabled(attrs)
    |> maybe_update_schedule_type(attrs)
    |> maybe_update_cron_expression(attrs)
    |> maybe_update_scheduled_at(attrs)
    |> maybe_update_timezone(attrs)
    |> maybe_update_parameters(attrs)
    |> maybe_update_mission(attrs)
    |> maybe_update_target(attrs)
    |> validate_timing_after_update()
  end

  @doc """
  Checks if the schedule is due to run.
  """
  @spec due?(t()) :: boolean()
  def due?(%__MODULE__{enabled: false}), do: false
  def due?(%__MODULE__{next_run_at: nil}), do: false

  def due?(%__MODULE__{next_run_at: next_run_at}) do
    DateTime.compare(DateTime.utc_now(), next_run_at) != :lt
  end

  @doc """
  Returns the list of valid schedule types.
  """
  @spec schedule_types() :: [atom()]
  def schedule_types, do: @schedule_types

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:error, {:required, key}}
      "" -> {:error, {:required, key}}
      value -> {:ok, value}
    end
  end

  defp validate_schedule_type(attrs) do
    case Map.get(attrs, :schedule_type) do
      nil -> {:error, {:required, :schedule_type}}
      type when is_atom(type) and type in @schedule_types -> {:ok, type}
      type when is_binary(type) -> validate_schedule_type_string(type)
      _ -> {:error, {:invalid, :schedule_type}}
    end
  end

  defp validate_schedule_type_string(type) do
    type_atom = String.to_atom(type)

    if type_atom in @schedule_types do
      {:ok, type_atom}
    else
      {:error, {:invalid, :schedule_type}}
    end
  end

  defp validate_schedule_timing(:cron, attrs) do
    case Map.get(attrs, :cron_expression) do
      nil -> {:error, {:required_for_cron, :cron_expression}}
      "" -> {:error, {:required_for_cron, :cron_expression}}
      _ -> :ok
    end
  end

  defp validate_schedule_timing(:once, attrs) do
    case Map.get(attrs, :scheduled_at) do
      nil -> {:error, {:required_for_once, :scheduled_at}}
      _ -> :ok
    end
  end

  defp validate_cron_expression(attrs) do
    cron = Map.get(attrs, :cron_expression)

    if cron && cron != "" do
      case Oban.Plugins.Cron.parse(cron) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, {:invalid, :cron_expression}}
      end
    else
      :ok
    end
  end

  defp maybe_update_name({:ok, schedule}, %{name: name}) when is_binary(name) and name != "" do
    {:ok, %{schedule | name: name}}
  end

  defp maybe_update_name(result, _), do: result

  defp maybe_update_description({:ok, schedule}, %{description: desc}) do
    {:ok, %{schedule | description: desc}}
  end

  defp maybe_update_description(result, _), do: result

  defp maybe_update_enabled({:ok, schedule}, %{enabled: enabled}) when is_boolean(enabled) do
    {:ok, %{schedule | enabled: enabled}}
  end

  defp maybe_update_enabled(result, _), do: result

  defp maybe_update_schedule_type({:ok, schedule}, %{schedule_type: type})
       when is_atom(type) and type in @schedule_types do
    {:ok, %{schedule | schedule_type: type}}
  end

  defp maybe_update_schedule_type({:ok, schedule}, %{schedule_type: type}) when is_binary(type) do
    type_atom = String.to_atom(type)

    if type_atom in @schedule_types do
      {:ok, %{schedule | schedule_type: type_atom}}
    else
      {:error, {:invalid, :schedule_type}}
    end
  end

  defp maybe_update_schedule_type(result, _), do: result

  defp maybe_update_cron_expression({:ok, schedule}, %{cron_expression: cron}) do
    {:ok, %{schedule | cron_expression: cron}}
  end

  defp maybe_update_cron_expression(result, _), do: result

  defp maybe_update_scheduled_at({:ok, schedule}, %{scheduled_at: scheduled_at}) do
    {:ok, %{schedule | scheduled_at: scheduled_at}}
  end

  defp maybe_update_scheduled_at(result, _), do: result

  defp maybe_update_timezone({:ok, schedule}, %{timezone: timezone}) when is_binary(timezone) do
    {:ok, %{schedule | timezone: timezone}}
  end

  defp maybe_update_timezone(result, _), do: result

  defp maybe_update_parameters({:ok, schedule}, %{parameters: params}) when is_map(params) do
    {:ok, %{schedule | parameters: params}}
  end

  defp maybe_update_parameters(result, _), do: result

  defp maybe_update_mission({:ok, schedule}, %{mission_id: mission_id}) do
    {:ok, %{schedule | mission_id: mission_id}}
  end

  defp maybe_update_mission(result, _), do: result

  defp maybe_update_target({:ok, schedule}, %{target_id: target_id}) do
    {:ok, %{schedule | target_id: target_id}}
  end

  defp maybe_update_target(result, _), do: result

  defp validate_timing_after_update({:ok, schedule} = result) do
    case schedule.schedule_type do
      :cron ->
        if schedule.cron_expression in [nil, ""] do
          {:error, {:required_for_cron, :cron_expression}}
        else
          result
        end

      :once ->
        if schedule.scheduled_at == nil do
          {:error, {:required_for_once, :scheduled_at}}
        else
          result
        end
    end
  end

  defp validate_timing_after_update(error), do: error
end
