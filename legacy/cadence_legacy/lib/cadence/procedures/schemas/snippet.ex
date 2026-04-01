defmodule Cadence.Procedures.Snippet do
  @moduledoc """
  A reusable snippet of procedure content.

  Snippets allow operators and procedure authors to save common patterns
  for reuse across procedures. Snippets can be:

  - `:step` - A single step with all its blocks
  - `:section` - A section with multiple steps
  - `:block_group` - A group of blocks (without step wrapper)

  ## Content Format

  The `content` field stores the full definition of the snippet:

  For step snippets:
      %{
        "name" => "verify_power",
        "title" => "Verify Power Status",
        "requires_signoff" => true,
        "blocks" => [
          %{"block_type" => "caution", "content" => %{...}},
          %{"block_type" => "telemetry_check", "content" => %{...}}
        ]
      }

  For section snippets:
      %{
        "name" => "Pre-Flight",
        "steps" => [
          %{"name" => "step1", ...},
          %{"name" => "step2", ...}
        ]
      }

  For block_group snippets:
      %{
        "blocks" => [
          %{"block_type" => "text", ...},
          %{"block_type" => "number_input", ...}
        ]
      }

  ## Organization Scoping

  Snippets are scoped to an organization, making them available to all
  procedures within that organization.

  ## Tags

  Snippets can be tagged for easier discovery:

      tags: ["safety", "thermal", "standard"]
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Organizations.Organization

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @snippet_types [:step, :section, :block_group]

  schema "procedure_snippets" do
    field :name, :string
    field :description, :string
    field :snippet_type, Ecto.Enum, values: @snippet_types
    field :tags, {:array, :string}, default: []
    field :content, :map

    belongs_to :organization, Organization
    belongs_to :created_by, User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:organization_id, :created_by_id, :name, :snippet_type, :content]
  @optional_fields [:description, :tags]

  @doc """
  Creates a changeset for a snippet.
  """
  def changeset(snippet, attrs) do
    snippet
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_tags()
    |> validate_content_for_type()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:created_by_id)
  end

  defp validate_tags(changeset) do
    case get_field(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        if Enum.all?(tags, &valid_tag?/1) do
          changeset
        else
          add_error(changeset, :tags, "contains invalid tags")
        end

      _ ->
        add_error(changeset, :tags, "must be a list of strings")
    end
  end

  defp valid_tag?(tag) when is_binary(tag) do
    byte_size(tag) > 0 and byte_size(tag) <= 50
  end

  defp valid_tag?(_), do: false

  defp validate_content_for_type(changeset) do
    snippet_type = get_field(changeset, :snippet_type)
    content = get_field(changeset, :content)

    case validate_content(snippet_type, content) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :content, message)
    end
  end

  defp validate_content(nil, _), do: :ok
  defp validate_content(_, nil), do: {:error, "is required"}

  defp validate_content(:step, content) do
    has_name = Map.has_key?(content, "name") or Map.has_key?(content, :name)
    has_blocks = Map.has_key?(content, "blocks") or Map.has_key?(content, :blocks)

    cond do
      not has_name -> {:error, "step snippet requires 'name' field"}
      not has_blocks -> {:error, "step snippet requires 'blocks' field"}
      true -> :ok
    end
  end

  defp validate_content(:section, content) do
    has_name = Map.has_key?(content, "name") or Map.has_key?(content, :name)
    has_steps = Map.has_key?(content, "steps") or Map.has_key?(content, :steps)

    cond do
      not has_name -> {:error, "section snippet requires 'name' field"}
      not has_steps -> {:error, "section snippet requires 'steps' field"}
      true -> :ok
    end
  end

  defp validate_content(:block_group, content) do
    has_blocks = Map.has_key?(content, "blocks") or Map.has_key?(content, :blocks)

    if has_blocks do
      :ok
    else
      {:error, "block_group snippet requires 'blocks' field"}
    end
  end

  @doc """
  Returns true if snippet matches any of the given tags.
  """
  def matches_tags?(%__MODULE__{tags: snippet_tags}, filter_tags) do
    Enum.any?(filter_tags, &(&1 in snippet_tags))
  end

  def snippet_types, do: @snippet_types
end
