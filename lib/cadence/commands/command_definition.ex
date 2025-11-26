defmodule Cadence.Commands.CommandDefinition do
  @moduledoc """
  Defines a spacecraft command within a DefinitionSet.

  CommandDefinition is part of the unified C&T database, versioned alongside
  telemetry packets within a DefinitionSet. This ensures commands and telemetry
  are always consistent.

  ## Safety Features (ADR-004)

  Commands support safety metadata for mission operations:

  - `is_hazardous` - Flags commands that could damage the spacecraft
  - `hazard_description` - Explains the potential hazard
  - `requires_confirmation` - Forces operator to confirm before execution
  - `allowed_phases` - Restricts command to specific mission phases

  ## Verification

  Commands can be configured for automatic verification by watching
  a telemetry item (CVT) for an expected value:

  - `has_verification` - Enables verification
  - `verification_item` - CVT item to watch (e.g., "HEALTH.CMD_ACCEPT_COUNT")
  - `verification_timeout_ms` - Time to wait for verification

  ## Example

      %CommandDefinition{
        name: "SAFE_MODE",
        opcode: 0x01,
        is_hazardous: true,
        hazard_description: "Will disable normal operations",
        requires_confirmation: true,
        allowed_phases: ["commissioning", "operations"],
        has_verification: true,
        verification_item: "HEALTH.MODE",
        verification_timeout_ms: 5000
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission
  alias Cadence.Telemetry.Database.DefinitionSet
  alias Cadence.Commands.CommandParameter

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @encoding_formats ["binary", "ascii", "json"]

  schema "command_definitions" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :definition_set, DefinitionSet

    # Command identification
    field :name, :string
    field :description, :string
    field :opcode, :integer

    # Safety configuration (ADR-004)
    field :is_hazardous, :boolean, default: false
    field :hazard_description, :string
    field :requires_confirmation, :boolean, default: false

    # Mission phase restrictions
    field :allowed_phases, {:array, :string}, default: []

    # Encoding configuration
    field :encoding_format, :string
    field :encoding_config, :map, default: %{}

    # Verification configuration
    field :has_verification, :boolean, default: false
    field :verification_item, :string
    field :verification_timeout_ms, :integer, default: 5000

    # Metadata
    field :metadata, :map, default: %{}

    # Parameters
    has_many :command_parameters, CommandParameter

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new or existing command definition.
  """
  def changeset(command_definition, attrs) do
    command_definition
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :opcode,
      :is_hazardous,
      :hazard_description,
      :requires_confirmation,
      :allowed_phases,
      :encoding_format,
      :encoding_config,
      :has_verification,
      :verification_item,
      :verification_timeout_ms,
      :metadata
    ])
    |> validate_required([:organization_id, :mission_id, :name])
    |> validate_inclusion(:encoding_format, @encoding_formats ++ [nil])
    |> validate_number(:opcode, greater_than_or_equal_to: 0, less_than: 65536)
    |> validate_number(:verification_timeout_ms, greater_than: 0)
    |> validate_hazardous_fields()
    |> validate_verification_fields()
    |> unique_constraint([:mission_id, :name])
    |> unique_constraint([:definition_set_id, :name],
      name: :command_definitions_definition_set_name_index
    )
  end

  # If is_hazardous is true, hazard_description should be provided
  defp validate_hazardous_fields(changeset) do
    is_hazardous = get_field(changeset, :is_hazardous)
    hazard_description = get_field(changeset, :hazard_description)

    if is_hazardous && (is_nil(hazard_description) || hazard_description == "") do
      add_error(changeset, :hazard_description, "is required when command is hazardous")
    else
      changeset
    end
  end

  # If has_verification is true, verification_item is required
  defp validate_verification_fields(changeset) do
    has_verification = get_field(changeset, :has_verification)
    verification_item = get_field(changeset, :verification_item)

    if has_verification && (is_nil(verification_item) || verification_item == "") do
      add_error(changeset, :verification_item, "is required when verification is enabled")
    else
      changeset
    end
  end

  @doc """
  Returns true if this command is hazardous.
  """
  def hazardous?(%__MODULE__{is_hazardous: true}), do: true
  def hazardous?(_), do: false

  @doc """
  Returns true if this command requires operator confirmation.
  """
  def requires_confirmation?(%__MODULE__{requires_confirmation: true}), do: true
  def requires_confirmation?(%__MODULE__{is_hazardous: true}), do: true
  def requires_confirmation?(_), do: false

  @doc """
  Checks if a command is allowed in the given mission phase.
  """
  def allowed_in_phase?(%__MODULE__{allowed_phases: []}, _phase), do: true
  def allowed_in_phase?(%__MODULE__{allowed_phases: phases}, phase), do: phase in phases

  @doc """
  Returns the list of valid encoding formats.
  """
  def valid_encoding_formats, do: @encoding_formats
end
