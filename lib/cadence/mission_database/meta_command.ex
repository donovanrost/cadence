defmodule Cadence.MissionDatabase.MetaCommand do
  @moduledoc """
  Command definition with arguments, constraints, and verifiers.

  MetaCommands define spacecraft commands including their arguments,
  safety classification, transmission constraints, and verification.

  ## Inheritance

  Commands support inheritance via `base_command_ref`. Child commands
  inherit arguments and can add new ones or assign fixed values to
  inherited arguments.

  ## Safety Classification

  Commands can be marked with significance levels (XTCE) or hazardous flags (OpenC3):

  - **significance**: none, watch, warning, distress, critical, severe
  - **is_hazardous**: Boolean flag requiring confirmation
  - **is_restricted**: Requires approval workflow

  ## Example

      %MetaCommand{
        name: "THRUSTER_FIRE",
        opcode: 0x45,
        is_hazardous: true,
        hazard_description: "Will fire attitude control thrusters",
        requires_confirmation: true,
        significance: :critical,
        allowed_phases: ["operations"],
        interlock: %CommandInterlock{
          previous_command_ref: "THRUSTER_ARM",
          verification_stage: :accepted
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{
    CommandInterlock,
    Argument,
    TransmissionConstraint,
    CommandVerifier,
    CommandContainer
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @significance_levels [:none, :watch, :warning, :distress, :critical, :severe]
  @encoding_formats [:binary, :ascii, :json]

  schema "mdb_meta_commands" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string
    field :short_description, :string

    # Inheritance
    field :base_command_ref, :string
    field :abstract, :boolean, default: false

    # Identification
    field :opcode, :integer

    # Safety classification (XTCE)
    field :significance, Ecto.Enum, values: @significance_levels, default: :none
    field :significance_reason, :string

    # Safety flags (OpenC3 style)
    field :is_hazardous, :boolean, default: false
    field :hazard_description, :string
    field :requires_confirmation, :boolean, default: false
    field :is_restricted, :boolean, default: false

    # Operational constraints
    field :allowed_phases, {:array, :string}, default: []
    field :disabled, :boolean, default: false
    field :disabled_reason, :string

    # Encoding
    field :encoding_format, Ecto.Enum, values: @encoding_formats
    field :encoding_config, :map, default: %{}

    # Interlock
    embeds_one :interlock, CommandInterlock, on_replace: :update

    # Associations
    has_many :arguments, Argument
    has_many :transmission_constraints, TransmissionConstraint
    has_many :verifiers, CommandVerifier
    has_one :command_container, CommandContainer

    # Related items
    field :related_telemetry_items, {:array, :string}, default: []
    field :related_screen, :string
    field :expected_response_container, :string

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a MetaCommand.
  """
  def changeset(meta_command, attrs) do
    meta_command
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :short_description,
      :base_command_ref,
      :abstract,
      :opcode,
      :significance,
      :significance_reason,
      :is_hazardous,
      :hazard_description,
      :requires_confirmation,
      :is_restricted,
      :allowed_phases,
      :disabled,
      :disabled_reason,
      :encoding_format,
      :encoding_config,
      :related_telemetry_items,
      :related_screen,
      :expected_response_container,
      :extensions
    ])
    |> cast_embed(:interlock)
    |> validate_required([:organization_id, :mission_id, :definition_set_id, :name])
    |> validate_inclusion(:significance, @significance_levels)
    |> validate_opcode()
    |> validate_hazardous_fields()
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_meta_commands_definition_set_name_index
    )
  end

  defp validate_opcode(changeset) do
    opcode = get_field(changeset, :opcode)

    if not is_nil(opcode) and (opcode < 0 or opcode > 65535) do
      add_error(changeset, :opcode, "must be between 0 and 65535")
    else
      changeset
    end
  end

  defp validate_hazardous_fields(changeset) do
    is_hazardous = get_field(changeset, :is_hazardous)
    hazard_description = get_field(changeset, :hazard_description)

    if is_hazardous and (is_nil(hazard_description) or hazard_description == "") do
      add_error(changeset, :hazard_description, "required when command is hazardous")
    else
      changeset
    end
  end

  @doc """
  Returns true if this command is hazardous.
  """
  def hazardous?(%__MODULE__{is_hazardous: true}), do: true
  def hazardous?(%__MODULE__{significance: sig}) when sig in [:critical, :severe], do: true
  def hazardous?(_), do: false

  @doc """
  Returns true if this command requires operator confirmation.
  """
  def requires_confirmation?(%__MODULE__{requires_confirmation: true}), do: true
  def requires_confirmation?(%__MODULE__{} = cmd), do: hazardous?(cmd)

  @doc """
  Checks if a command is allowed in the given mission phase.
  """
  def allowed_in_phase?(%__MODULE__{allowed_phases: []}, _phase), do: true
  def allowed_in_phase?(%__MODULE__{allowed_phases: phases}, phase), do: phase in phases

  @doc """
  Returns true if this command is abstract.
  """
  def abstract?(%__MODULE__{abstract: true}), do: true
  def abstract?(_), do: false

  @doc """
  Returns true if this command has a base command.
  """
  def has_base?(%__MODULE__{base_command_ref: nil}), do: false
  def has_base?(%__MODULE__{base_command_ref: ""}), do: false
  def has_base?(_), do: true

  @doc """
  Returns the list of valid significance levels.
  """
  def valid_significance_levels, do: @significance_levels

  @doc """
  Returns the list of valid encoding formats.
  """
  def valid_encoding_formats, do: @encoding_formats
end
