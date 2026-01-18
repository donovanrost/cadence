defmodule Cadence.Runtime.Missions.MissionStatus do
  @moduledoc """
  Runtime status for a mission instance, reported via Phoenix.Tracker.

  This struct represents the observable state of a running mission in the
  data plane. The control plane reconciler uses this information to detect
  drift between desired and actual state.

  ## Status Values

  - `:starting` - Mission is initializing, components coming up
  - `:ready` - All components ready and processing
  - `:degraded` - Some components failed but mission is partially functional
  - `:stopping` - Mission is shutting down

  ## Conditions

  Conditions provide fine-grained status for each component:

      [
        {:cvt, :ready, "Current value table initialized"},
        {:interfaces, :ready, "3 of 3 interfaces connected"},
        {:pipeline, :ready, "Telemetry pipeline processing"},
        {:commands, :degraded, "Target queue backpressure detected"}
      ]

  ## Usage

      # Create initial status when mission starts
      status = MissionStatus.new(mission_id, config_generation)

      # Update as components become ready
      status = MissionStatus.set_condition(status, :cvt, :ready)
      status = MissionStatus.set_condition(status, :interfaces, :ready)

      # Compute overall status from conditions
      status = MissionStatus.compute_status(status)
  """

  alias Cadence.Time, as: CadenceTime

  @type condition_type ::
          :cvt
          | :interfaces
          | :pipeline
          | :commands
          | :limits
          | :alarms
          | :automations
          | :procedures

  @type condition_status :: :pending | :ready | :degraded | :failed

  @type condition :: {condition_type(), condition_status(), String.t()}

  @type status :: :starting | :ready | :degraded | :stopping

  @type t :: %__MODULE__{
          mission_id: String.t(),
          config_generation: integer(),
          observed_generation: integer(),
          started_at: DateTime.t(),
          status: status(),
          conditions: [condition()],
          node: node()
        }

  defstruct [
    :mission_id,
    :config_generation,
    :observed_generation,
    :started_at,
    :status,
    :node,
    conditions: []
  ]

  @doc """
  Creates a new MissionStatus for a starting mission.
  """
  @spec new(String.t(), integer()) :: t()
  def new(mission_id, config_generation) do
    %__MODULE__{
      mission_id: mission_id,
      config_generation: config_generation,
      observed_generation: config_generation,
      started_at: CadenceTime.now(),
      status: :starting,
      conditions: initial_conditions(),
      node: node()
    }
  end

  @doc """
  Sets a condition's status and message.
  """
  @spec set_condition(t(), condition_type(), condition_status(), String.t()) :: t()
  def set_condition(%__MODULE__{} = status, type, condition_status, message \\ "") do
    conditions =
      status.conditions
      |> Enum.reject(fn {t, _, _} -> t == type end)
      |> Kernel.++([{type, condition_status, message}])

    %{status | conditions: conditions}
  end

  @doc """
  Gets a condition by type.
  """
  @spec get_condition(t(), condition_type()) :: condition() | nil
  def get_condition(%__MODULE__{conditions: conditions}, type) do
    Enum.find(conditions, fn {t, _, _} -> t == type end)
  end

  @doc """
  Computes overall status from conditions.

  - All conditions `:ready` -> `:ready`
  - Any condition `:failed` -> `:degraded`
  - Any condition `:degraded` -> `:degraded`
  - Otherwise -> `:starting`
  """
  @spec compute_status(t()) :: t()
  def compute_status(%__MODULE__{conditions: conditions} = status) do
    computed =
      cond do
        Enum.all?(conditions, fn {_, s, _} -> s == :ready end) ->
          :ready

        Enum.any?(conditions, fn {_, s, _} -> s in [:failed, :degraded] end) ->
          :degraded

        true ->
          :starting
      end

    %{status | status: computed}
  end

  @doc """
  Updates the observed generation after config is applied.
  """
  @spec update_observed_generation(t(), integer()) :: t()
  def update_observed_generation(%__MODULE__{} = status, generation) do
    %{status | observed_generation: generation}
  end

  @doc """
  Marks the status as stopping.
  """
  @spec stopping(t()) :: t()
  def stopping(%__MODULE__{} = status) do
    %{status | status: :stopping}
  end

  @doc """
  Returns true if the mission has converged (observed matches config generation).
  """
  @spec converged?(t()) :: boolean()
  def converged?(%__MODULE__{config_generation: config, observed_generation: observed}) do
    config == observed
  end

  @doc """
  Converts status to a map suitable for Phoenix.Tracker metadata.
  """
  @spec to_tracker_meta(t()) :: map()
  def to_tracker_meta(%__MODULE__{} = status) do
    %{
      mission_id: status.mission_id,
      config_generation: status.config_generation,
      observed_generation: status.observed_generation,
      started_at: status.started_at,
      status: status.status,
      conditions: status.conditions,
      node: status.node
    }
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp initial_conditions do
    [
      {:cvt, :pending, "Initializing"},
      {:interfaces, :pending, "Initializing"},
      {:pipeline, :pending, "Initializing"},
      {:commands, :pending, "Initializing"},
      {:limits, :pending, "Initializing"},
      {:alarms, :pending, "Initializing"}
    ]
  end
end
