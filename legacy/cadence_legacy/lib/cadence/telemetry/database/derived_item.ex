defmodule Cadence.Telemetry.Database.DerivedItem do
  @moduledoc """
  Represents a derived telemetry item as a mission-scoped runtime overlay.

  Unlike packet items which are part of an immutable DefinitionSet, derived items
  exist outside the versioned database. This allows operators to:

  - Add derived calculations without modifying the C&T database
  - Persist derived items across DefinitionSet version updates
  - Create mission-specific computations that don't belong in flight software

  ## Example

      # Create a derived item that averages two temperatures
      {:ok, derived} = DerivedItem.create(%{
        mission_id: mission.id,
        organization_id: mission.organization_id,
        name: "TEMP_AVG",
        expression: "(HEALTH.CPU_TEMP + HEALTH.GPU_TEMP) / 2",
        units: "°C"
      })

  ## Expression Syntax

  All variable references must be fully qualified using `PACKET_NAME.ITEM_NAME` notation.
  Expressions support:

  - Arithmetic: `+`, `-`, `*`, `/`
  - Functions: `abs`, `sqrt`, `min`, `max`, `pow`, `round`, `floor`, `ceil`, `clamp`
  - Conditionals: `if CONDITION then VALUE else VALUE`
  - Comparisons: `<`, `>`, `<=`, `>=`, `==`, `!=`

  Source items are automatically extracted from the expression.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @data_types ["float", "int", "uint", "string", "boolean"]

  schema "derived_items" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission

    # Item identification
    field :name, :string
    field :description, :string

    # Expression configuration
    field :expression, :string
    field :source_items, {:array, :string}, default: []
    field :cross_packet_items, {:array, :map}, default: []

    # Output configuration
    field :units, :string
    field :format_string, :string
    field :data_type, :string, default: "float"

    # Display configuration
    field :display_order, :integer
    field :metadata, :map, default: %{}

    # Runtime control
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new or existing derived item.

  Note: `source_items` is auto-extracted from the expression if not provided.
  """
  def changeset(derived_item, attrs) do
    derived_item
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :name,
      :description,
      :expression,
      :source_items,
      :units,
      :format_string,
      :data_type,
      :display_order,
      :metadata,
      :enabled
    ])
    |> validate_required([:organization_id, :mission_id, :name, :expression])
    |> validate_inclusion(:data_type, @data_types)
    |> validate_expression()
    |> unique_constraint([:mission_id, :name])
  end

  # Validate that the expression is syntactically valid
  defp validate_expression(changeset) do
    expression = get_field(changeset, :expression)

    if expression && expression != "" do
      alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator

      case ExpressionEvaluator.validate(expression) do
        :ok ->
          # Also extract and store source items if not provided
          changeset
          |> maybe_extract_source_items(expression)

        {:error, reason} ->
          add_error(changeset, :expression, ExpressionEvaluator.format_error(reason))
      end
    else
      changeset
    end
  end

  # Auto-extract source items from expression if not provided
  defp maybe_extract_source_items(changeset, expression) do
    source_items = get_field(changeset, :source_items)

    if is_nil(source_items) || source_items == [] do
      alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator

      case ExpressionEvaluator.extract_variables(expression) do
        {:ok, variables} ->
          put_change(changeset, :source_items, variables)

        {:error, reason} ->
          add_error(changeset, :expression, ExpressionEvaluator.format_error(reason))
      end
    else
      changeset
    end
  end

  @doc """
  Creates a new derived item.

  Automatically invalidates the cache for the mission.
  """
  def create(attrs) do
    result =
      %__MODULE__{}
      |> changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, derived_item} ->
        invalidate_cache(derived_item.mission_id)
        {:ok, derived_item}

      error ->
        error
    end
  end

  @doc """
  Updates an existing derived item.

  Automatically invalidates the cache for the mission.
  """
  def update(%__MODULE__{} = derived_item, attrs) do
    result =
      derived_item
      |> changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        invalidate_cache(updated.mission_id)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Deletes a derived item.

  Automatically invalidates the cache for the mission.
  """
  def delete(%__MODULE__{} = derived_item) do
    mission_id = derived_item.mission_id

    case Repo.delete(derived_item) do
      {:ok, deleted} ->
        invalidate_cache(mission_id)
        {:ok, deleted}

      error ->
        error
    end
  end

  # Invalidate the cache for a mission (if cache is running)
  defp invalidate_cache(mission_id) do
    alias Cadence.Runtime.Telemetry.DerivedItems.Cache

    if Process.whereis(Cache) do
      Cache.invalidate(mission_id)
    end
  end

  @doc """
  Gets a derived item by ID.
  """
  def get(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets a derived item by ID, raises if not found.
  """
  def get!(id) do
    Repo.get!(__MODULE__, id)
  end

  @doc """
  Gets a derived item by name for a mission.
  """
  def get_by_name(mission_id, name) do
    from(d in __MODULE__,
      where: d.mission_id == ^mission_id,
      where: d.name == ^name
    )
    |> Repo.one()
  end

  @doc """
  Lists all enabled derived items for a mission.
  """
  def list_enabled(mission_id) do
    from(d in __MODULE__,
      where: d.mission_id == ^mission_id,
      where: d.enabled == true,
      order_by: [asc: d.display_order, asc: d.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists all derived items for a mission (including disabled).
  """
  def list_all(mission_id) do
    from(d in __MODULE__,
      where: d.mission_id == ^mission_id,
      order_by: [asc: d.display_order, asc: d.name]
    )
    |> Repo.all()
  end

  @doc """
  Enables a derived item.
  """
  def enable(%__MODULE__{} = derived_item) do
    __MODULE__.update(derived_item, %{enabled: true})
  end

  @doc """
  Disables a derived item.
  """
  def disable(%__MODULE__{} = derived_item) do
    __MODULE__.update(derived_item, %{enabled: false})
  end

  @doc """
  Converts a derived item to the map format expected by the DerivedItems compute module.

  Only includes the expression - source items are extracted dynamically when needed
  for dependency sorting.
  """
  def to_compute_format(%__MODULE__{} = derived_item) do
    %{
      name: derived_item.name,
      data_type: :derived,
      derived_config: %{
        "expression" => derived_item.expression
      }
    }
  end
end
