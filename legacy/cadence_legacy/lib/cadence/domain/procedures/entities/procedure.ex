defmodule Cadence.Domain.Procedures.Entities.Procedure do
  @moduledoc """
  Pure domain entity representing a procedure definition.

  Procedures are versioned containers for operational sequences.
  They can be either DAG-based (step workflows) or script-based (Lua code).

  ## Usage

      {:ok, procedure} = Procedure.new(%{
        organization_id: "org-uuid",
        mission_id: "mission-uuid",
        name: "Power On Sequence",
        type: :dag
      })
  """

  @type procedure_type :: :dag | :script

  @type t :: %__MODULE__{
          id: String.t() | nil,
          organization_id: String.t(),
          mission_id: String.t() | nil,
          name: String.t(),
          description: String.t() | nil,
          type: procedure_type(),
          tags: [String.t()],
          current_version_id: String.t() | nil,
          created_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :organization_id,
    :mission_id,
    :name,
    :description,
    :type,
    :current_version_id,
    :created_at,
    tags: []
  ]

  @doc """
  Creates a new Procedure entity.

  ## Required Fields

  - `:organization_id` - Organization this procedure belongs to
  - `:name` - Procedure name

  ## Optional Fields

  - `:mission_id` - Mission scope (nil for org-level procedures)
  - `:description` - Procedure description
  - `:type` - :dag or :script (default: :dag)
  - `:tags` - List of tags
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs, [:organization_id, :name]),
         :ok <- validate_name(attrs[:name]),
         :ok <- validate_type(attrs[:type]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         organization_id: attrs[:organization_id],
         mission_id: attrs[:mission_id],
         name: attrs[:name],
         description: attrs[:description],
         type: attrs[:type] || :dag,
         tags: normalize_tags(attrs[:tags] || []),
         current_version_id: attrs[:current_version_id],
         created_at: attrs[:created_at]
       }}
    end
  end

  @doc """
  Updates the procedure with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = procedure, attrs) do
    with :ok <- validate_name(attrs[:name] || procedure.name) do
      {:ok,
       %{
         procedure
         | name: attrs[:name] || procedure.name,
           description: Map.get(attrs, :description, procedure.description),
           tags: normalize_tags(attrs[:tags] || procedure.tags)
       }}
    end
  end

  @doc """
  Sets the current approved version.
  """
  @spec set_current_version(t(), String.t()) :: {:ok, t()}
  def set_current_version(%__MODULE__{} = procedure, version_id) do
    {:ok, %{procedure | current_version_id: version_id}}
  end

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

  defp validate_type(nil), do: :ok
  defp validate_type(:dag), do: :ok
  defp validate_type(:script), do: :ok
  defp validate_type(_), do: {:error, :invalid_type}

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
  end

  defp normalize_tags(_), do: []
end
