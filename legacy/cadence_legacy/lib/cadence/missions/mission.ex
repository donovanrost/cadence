defmodule Cadence.Missions.Mission do
  @moduledoc """
  Mission schema representing a spacecraft mission within an organization.

  A mission is the primary unit of runtime isolation in Cadence. Each mission has:
  - Dedicated supervision tree
  - Mission-scoped Current Value Table (CVT)
  - Independent telemetry and command processing
  - One or more targets (spacecraft, ground stations, etc.)

  Missions progress through phases: planning → testing → operational → decommissioned
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t(),
          name: String.t(),
          slug: String.t(),
          description: String.t() | nil,
          status: String.t(),
          phase: String.t(),
          config: map(),
          metadata: map(),
          config_generation: integer(),
          start_date: DateTime.t() | nil,
          end_date: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "missions" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "inactive"
    field :phase, :string, default: "planning"

    # Configuration
    field :config, :map, default: %{}
    field :metadata, :map, default: %{}

    # Config generation - monotonically increasing version number for reconciliation
    field :config_generation, :integer, default: 1

    # Operational windows
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    # Associations
    belongs_to :organization, Cadence.Organizations.Organization
    has_many :targets, Cadence.Targets.Target
    has_many :mission_memberships, Cadence.Missions.MissionMembership
    has_many :users, through: [:mission_memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new mission.
  """
  def changeset(mission, attrs) do
    mission
    |> cast(attrs, [
      :organization_id,
      :name,
      :slug,
      :description,
      :status,
      :phase,
      :config,
      :metadata,
      :start_date,
      :end_date
    ])
    |> validate_required([:organization_id, :name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
    |> validate_inclusion(:status, ["inactive", "active", "suspended"])
    |> validate_inclusion(:phase, ["planning", "testing", "operational", "decommissioned"])
    |> validate_date_range()
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :slug])
  end

  @doc """
  Changeset for updating mission status or configuration.
  """
  def update_changeset(mission, attrs) do
    mission
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :phase,
      :config,
      :metadata,
      :start_date,
      :end_date
    ])
    |> validate_required([:name])
    |> validate_inclusion(:status, ["inactive", "active", "suspended"])
    |> validate_inclusion(:phase, ["planning", "testing", "operational", "decommissioned"])
    |> validate_date_range()
    |> validate_phase_transition(mission)
  end

  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && DateTime.compare(start_date, end_date) == :gt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end

  defp validate_phase_transition(changeset, mission) do
    old_phase = mission.phase
    new_phase = get_change(changeset, :phase)

    if new_phase && !valid_phase_transition?(old_phase, new_phase) do
      add_error(
        changeset,
        :phase,
        "invalid phase transition from #{old_phase} to #{new_phase}"
      )
    else
      changeset
    end
  end

  defp valid_phase_transition?(from, to) do
    allowed_transitions = %{
      "planning" => ["testing", "decommissioned"],
      "testing" => ["operational", "planning", "decommissioned"],
      "operational" => ["decommissioned"],
      "decommissioned" => []
    }

    to in Map.get(allowed_transitions, from, [])
  end
end
