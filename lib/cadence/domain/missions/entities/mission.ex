defmodule Cadence.Domain.Missions.Entities.Mission do
  @moduledoc """
  Pure domain entity representing a spacecraft mission within an organization.

  A mission is the primary unit of runtime isolation in Cadence. Each mission has:
  - Dedicated supervision tree
  - Mission-scoped Current Value Table (CVT)
  - Independent telemetry and command processing
  - One or more targets (spacecraft, ground stations, etc.)

  Missions progress through phases: planning -> testing -> operational -> decommissioned

  ## Usage

      {:ok, mission} = Mission.new(%{
        organization_id: org_id,
        name: "ISS Operations",
        slug: "iss-ops"
      })

      # Start the mission runtime
      {:ok, mission} = Mission.start(mission)

      # Advance through phases
      {:ok, mission} = Mission.advance_phase(mission, :testing)
  """

  alias Cadence.Domain.Missions.ValueObjects.MissionStatus
  alias Cadence.Domain.Missions.ValueObjects.MissionPhase

  @type t :: %__MODULE__{
          id: String.t() | nil,
          organization_id: String.t(),
          name: String.t(),
          slug: String.t(),
          description: String.t() | nil,
          status: MissionStatus.t(),
          phase: MissionPhase.t(),
          config: map(),
          metadata: map(),
          start_date: DateTime.t() | nil,
          end_date: DateTime.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :organization_id,
    :name,
    :slug,
    :description,
    :status,
    :phase,
    :start_date,
    :end_date,
    :created_at,
    :updated_at,
    config: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new Mission entity.

  ## Required Fields

  - `:organization_id` - Parent organization ID
  - `:name` - Mission display name
  - `:slug` - URL-safe identifier (lowercase alphanumeric with hyphens)

  ## Optional Fields

  - `:description` - Mission description
  - `:status` - Runtime status (default: :inactive)
  - `:phase` - Lifecycle phase (default: :planning)
  - `:config` - Mission configuration map
  - `:metadata` - Additional metadata map
  - `:start_date` - Planned start date
  - `:end_date` - Planned end date
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs, [:organization_id, :name, :slug]),
         :ok <- validate_name(attrs[:name]),
         :ok <- validate_slug(attrs[:slug]),
         {:ok, status} <- parse_status(attrs[:status]),
         {:ok, phase} <- parse_phase(attrs[:phase]),
         :ok <- validate_date_range(attrs[:start_date], attrs[:end_date]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         organization_id: attrs[:organization_id],
         name: attrs[:name],
         slug: attrs[:slug],
         description: attrs[:description],
         status: status,
         phase: phase,
         config: attrs[:config] || %{},
         metadata: attrs[:metadata] || %{},
         start_date: attrs[:start_date],
         end_date: attrs[:end_date],
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates the mission with new attributes.

  Note: slug and organization_id cannot be changed after creation.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = mission, attrs) do
    with :ok <- validate_name(attrs[:name] || mission.name),
         {:ok, status} <- maybe_parse_status(attrs[:status], mission.status),
         {:ok, phase} <- maybe_parse_phase(attrs[:phase], mission.phase),
         :ok <-
           validate_date_range(
             attrs[:start_date] || mission.start_date,
             attrs[:end_date] || mission.end_date
           ) do
      {:ok,
       %{
         mission
         | name: attrs[:name] || mission.name,
           description: Map.get(attrs, :description, mission.description),
           status: status,
           phase: phase,
           config: Map.merge(mission.config, attrs[:config] || %{}),
           metadata: Map.merge(mission.metadata, attrs[:metadata] || %{}),
           start_date: attrs[:start_date] || mission.start_date,
           end_date: attrs[:end_date] || mission.end_date,
           updated_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Starts the mission runtime.
  """
  @spec start(t()) :: {:ok, t()} | {:error, term()}
  def start(%__MODULE__{status: status} = mission) do
    with :ok <- MissionStatus.validate_transition(status, :active) do
      {:ok, %{mission | status: :active, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Stops the mission runtime.
  """
  @spec stop(t()) :: {:ok, t()} | {:error, term()}
  def stop(%__MODULE__{status: status} = mission) do
    with :ok <- MissionStatus.validate_transition(status, :inactive) do
      {:ok, %{mission | status: :inactive, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Suspends the mission runtime.
  """
  @spec suspend(t()) :: {:ok, t()} | {:error, term()}
  def suspend(%__MODULE__{status: status} = mission) do
    with :ok <- MissionStatus.validate_transition(status, :suspended) do
      {:ok, %{mission | status: :suspended, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Resumes a suspended mission.
  """
  @spec resume(t()) :: {:ok, t()} | {:error, term()}
  def resume(%__MODULE__{status: status} = mission) do
    with :ok <- MissionStatus.validate_transition(status, :active) do
      {:ok, %{mission | status: :active, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Advances the mission to a new phase.
  """
  @spec advance_phase(t(), MissionPhase.t()) :: {:ok, t()} | {:error, term()}
  def advance_phase(%__MODULE__{phase: current} = mission, new_phase) do
    with :ok <- MissionPhase.validate_transition(current, new_phase) do
      {:ok, %{mission | phase: new_phase, updated_at: DateTime.utc_now()}}
    end
  end

  @doc """
  Returns true if the mission runtime is running.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{status: status}), do: MissionStatus.running?(status)

  @doc """
  Returns true if the mission is operational.
  """
  @spec operational?(t()) :: boolean()
  def operational?(%__MODULE__{phase: phase}), do: MissionPhase.operational?(phase)

  @doc """
  Returns true if the mission is decommissioned.
  """
  @spec decommissioned?(t()) :: boolean()
  def decommissioned?(%__MODULE__{phase: phase}), do: MissionPhase.terminal?(phase)

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, fields) do
    missing = Enum.filter(fields, fn field -> is_nil(attrs[field]) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_name(nil), do: :ok

  defp validate_name(name) when is_binary(name) do
    cond do
      String.length(name) < 1 -> {:error, :name_too_short}
      String.length(name) > 255 -> {:error, :name_too_long}
      true -> :ok
    end
  end

  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_slug(nil), do: :ok

  defp validate_slug(slug) when is_binary(slug) do
    cond do
      String.length(slug) < 1 ->
        {:error, :slug_too_short}

      String.length(slug) > 100 ->
        {:error, :slug_too_long}

      not Regex.match?(~r/^[a-z0-9-]+$/, slug) ->
        {:error, :invalid_slug_format}

      true ->
        :ok
    end
  end

  defp validate_slug(_), do: {:error, :invalid_slug}

  defp validate_date_range(nil, _), do: :ok
  defp validate_date_range(_, nil), do: :ok

  defp validate_date_range(start_date, end_date) do
    if DateTime.compare(start_date, end_date) == :gt do
      {:error, :end_date_before_start_date}
    else
      :ok
    end
  end

  defp parse_status(nil), do: {:ok, MissionStatus.initial()}
  defp parse_status(status) when is_atom(status), do: MissionStatus.parse(status)
  defp parse_status(status) when is_binary(status), do: MissionStatus.parse(status)
  defp parse_status(_), do: {:error, :invalid_status}

  defp maybe_parse_status(nil, current), do: {:ok, current}
  defp maybe_parse_status(status, _current), do: parse_status(status)

  defp parse_phase(nil), do: {:ok, MissionPhase.initial()}
  defp parse_phase(phase) when is_atom(phase), do: MissionPhase.parse(phase)
  defp parse_phase(phase) when is_binary(phase), do: MissionPhase.parse(phase)
  defp parse_phase(_), do: {:error, :invalid_phase}

  defp maybe_parse_phase(nil, current), do: {:ok, current}
  defp maybe_parse_phase(phase, _current), do: parse_phase(phase)
end

# Implement Bucketable protocol for recording context
defimpl Cadence.Buckets.Bucketable, for: Cadence.Domain.Missions.Entities.Mission do
  def bucket_type(_), do: :mission
  def bucketable_type(_), do: :mission
  def bucket_name(mission), do: mission.name
  def bucket_started_at(mission), do: mission.start_date
  def bucket_ended_at(mission), do: mission.end_date
  def parent_bucket_id(_), do: nil
  def bucket_metadata(mission), do: mission.metadata || %{}
end
