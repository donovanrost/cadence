defmodule Cadence.MissionDatabase.Container do
  @moduledoc """
  Telemetry packet/container definition.

  Containers define the structure of telemetry packets. They support:
  - **Inheritance**: Containers can inherit from base containers
  - **Restriction Criteria**: Conditions that identify which container matches incoming bytes
  - **Entries**: References to parameters, fixed values, or nested containers

  ## Inheritance

  Containers can inherit from a base container using `base_container_ref`.
  The child container inherits all entries from the parent and can add
  additional entries or override identification criteria.

  ## Restriction Criteria (Packet Identification)

  XTCE uses RestrictionCriteria to identify which container definition
  matches incoming telemetry. This is evaluated against the packet contents.

  For CCSDS packets, the `apid` field provides a shortcut for identification.

  ## Example: Base Container

      %Container{
        name: "CCSDSPacket",
        abstract: true,
        byte_order: :big_endian
      }

  ## Example: Concrete Container

      %Container{
        name: "HEALTH_TLM",
        base_container_ref: "CCSDSPacket",
        apid: 100,
        restriction_criteria: %MatchCriteria{
          parameter_ref: "CCSDS.APID",
          comparison: :equal,
          value: "100"
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{ContainerEntry, MatchCriteria, Stream}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @byte_orders [:big_endian, :little_endian]

  schema "mdb_containers" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string
    field :short_description, :string

    # Inheritance
    field :base_container_ref, :string
    field :abstract, :boolean, default: false

    # Identification
    embeds_one :restriction_criteria, MatchCriteria, on_replace: :update
    field :apid, :integer
    field :packet_type, :integer

    # Structure
    field :byte_order, Ecto.Enum, values: @byte_orders, default: :big_endian

    # Sync pattern
    field :sync_pattern, :binary
    field :sync_pattern_offset_bits, :integer

    # Size
    field :size_in_bits, :integer
    field :max_size_in_bits, :integer

    # Rate
    field :expected_rate_hz, :float
    field :rate_tolerance_percent, :float

    # Processing hints
    field :allow_short, :boolean, default: false
    field :hidden, :boolean, default: false

    # Stream
    belongs_to :stream, Stream

    # Entries
    has_many :container_entries, ContainerEntry

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a Container.
  """
  def changeset(container, attrs) do
    container
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :short_description,
      :base_container_ref,
      :abstract,
      :apid,
      :packet_type,
      :byte_order,
      :sync_pattern,
      :sync_pattern_offset_bits,
      :size_in_bits,
      :max_size_in_bits,
      :expected_rate_hz,
      :rate_tolerance_percent,
      :allow_short,
      :hidden,
      :stream_id,
      :extensions
    ])
    |> cast_embed(:restriction_criteria)
    |> validate_required([:organization_id, :mission_id, :definition_set_id, :name])
    |> validate_inclusion(:byte_order, @byte_orders)
    |> validate_apid()
    |> validate_size()
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_containers_definition_set_name_index
    )
  end

  defp validate_apid(changeset) do
    apid = get_field(changeset, :apid)

    if not is_nil(apid) and (apid < 0 or apid > 2047) do
      add_error(changeset, :apid, "must be between 0 and 2047")
    else
      changeset
    end
  end

  defp validate_size(changeset) do
    size = get_field(changeset, :size_in_bits)
    max_size = get_field(changeset, :max_size_in_bits)

    cond do
      not is_nil(size) and not is_nil(max_size) and size > max_size ->
        add_error(changeset, :size_in_bits, "cannot be greater than max_size_in_bits")

      not is_nil(size) and size < 0 ->
        add_error(changeset, :size_in_bits, "must be non-negative")

      not is_nil(max_size) and max_size < 0 ->
        add_error(changeset, :max_size_in_bits, "must be non-negative")

      true ->
        changeset
    end
  end

  @doc """
  Returns true if this container is abstract (cannot be directly instantiated).
  """
  def abstract?(%__MODULE__{abstract: true}), do: true
  def abstract?(_), do: false

  @doc """
  Returns true if this container has a base container.
  """
  def has_base?(%__MODULE__{base_container_ref: nil}), do: false
  def has_base?(%__MODULE__{base_container_ref: ""}), do: false
  def has_base?(_), do: true

  @doc """
  Returns the list of valid byte orders.
  """
  def valid_byte_orders, do: @byte_orders
end
