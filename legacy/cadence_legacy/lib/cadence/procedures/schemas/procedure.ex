defmodule Cadence.Procedures.Procedure do
  @moduledoc """
  A procedure definition.

  Procedures can be either:
  - `:dag` - Step-based DAG (directed acyclic graph) with parallel execution support
  - `:script` - Raw Lua code for complex/custom operations

  Procedures are versioned - edits create new versions. The `current_version_id`
  points to the latest approved version (or latest draft if none approved).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.ProcedureVersion

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedures" do
    field :name, :string
    field :description, :string
    field :type, Ecto.Enum, values: [:dag, :script], default: :dag
    field :tags, {:array, :string}, default: []

    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :current_version, ProcedureVersion

    has_many :versions, ProcedureVersion

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :organization_id]
  @optional_fields [:description, :type, :mission_id, :current_version_id, :tags]

  def changeset(procedure, attrs) do
    procedure
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_tags()
    |> unique_constraint([:organization_id, :mission_id, :name],
      name: :procedures_org_mission_name_index,
      message: "procedure name must be unique within the mission"
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end

  defp validate_tags(changeset) do
    case get_field(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        # First normalize, then validate
        normalized = tags |> Enum.map(&normalize_tag/1) |> Enum.uniq()

        if Enum.all?(normalized, &valid_tag?/1) do
          put_change(changeset, :tags, normalized)
        else
          add_error(
            changeset,
            :tags,
            "tags must contain only lowercase letters, numbers, and hyphens (max 50 chars)"
          )
        end

      _ ->
        add_error(changeset, :tags, "must be a list")
    end
  end

  defp valid_tag?(tag) when is_binary(tag) do
    tag != "" and String.match?(tag, ~r/^[a-z0-9][a-z0-9-]*$/) and String.length(tag) <= 50
  end

  defp valid_tag?(_), do: false

  defp normalize_tag(tag) do
    tag |> String.downcase() |> String.trim()
  end
end
