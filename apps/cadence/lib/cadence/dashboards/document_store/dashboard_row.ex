defmodule Cadence.Dashboards.DocumentStore.DashboardRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.Document
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:dashboard_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "ops_dashboards" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:name, :string)
    field(:description, :string)
    field(:document, :map, default: %{})
    field(:latest_version, :integer)
    field(:draft_version, :integer)
    field(:published_version, :integer)
    field(:lifecycle_state, :string, default: "active")
    field(:published_at, :utc_datetime_usec)
    field(:published_by, :string)
    field(:lock_version, :integer, default: 1)

    timestamps()
  end

  @document_fields [
    :dashboard_id,
    :organization_id,
    :mission_id,
    :name,
    :description,
    :document,
    :latest_version,
    :draft_version,
    :lifecycle_state
  ]
  @required_fields [:dashboard_id, :mission_id, :name, :document, :lifecycle_state]
  @publish_fields [:published_version, :published_at, :published_by, :draft_version]
  @lifecycle_fields [:lifecycle_state]

  @spec document_changeset(Document.t()) :: Ecto.Changeset.t()
  def document_changeset(%Document{} = document) do
    document_changeset(%__MODULE__{}, document)
  end

  @spec document_changeset(struct(), Document.t()) :: Ecto.Changeset.t()
  def document_changeset(%__MODULE__{} = row, %Document{} = document) do
    row
    |> cast(document_attrs(document, row), @document_fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 500)
    |> unique_constraint([:mission_id, :dashboard_id], name: :ops_dashboards_scope_idx)
  end

  @spec to_document(struct()) :: Document.t()
  def to_document(%__MODULE__{document: document} = row) do
    case document do
      document when is_map(document) and document != %{} ->
        Document.from_map(document)

      _missing ->
        %Document{
          dashboard_id: row.dashboard_id,
          organization_id: row.organization_id,
          mission_id: row.mission_id,
          name: row.name,
          description: row.description
        }
    end
  end

  @spec document_version(struct()) :: pos_integer() | nil
  def document_version(%__MODULE__{} = row) do
    row
    |> to_document()
    |> Document.version()
  end

  @spec latest_version(struct()) :: pos_integer() | nil
  def latest_version(%__MODULE__{latest_version: version})
      when is_integer(version) and version > 0,
      do: version

  def latest_version(%__MODULE__{} = row), do: document_version(row)

  @spec draft_version(struct()) :: pos_integer() | nil
  def draft_version(%__MODULE__{draft_version: version}) when is_integer(version) and version > 0,
    do: version

  def draft_version(%__MODULE__{} = row), do: latest_version(row)

  @spec published_version(struct()) :: pos_integer() | nil
  def published_version(%__MODULE__{published_version: version})
      when is_integer(version) and version > 0,
      do: version

  def published_version(%__MODULE__{}), do: nil

  @spec archived?(struct()) :: boolean()
  def archived?(%__MODULE__{lifecycle_state: "archived"}), do: true
  def archived?(%__MODULE__{}), do: false

  @spec publish_changeset(struct(), pos_integer(), DateTime.t(), binary() | nil) ::
          Ecto.Changeset.t()
  def publish_changeset(
        %__MODULE__{} = row,
        version,
        %DateTime{} = published_at,
        published_by
      )
      when is_integer(version) and version > 0 and
             (is_binary(published_by) or is_nil(published_by)) do
    row
    |> cast(
      %{
        published_version: version,
        published_at: published_at,
        published_by: published_by,
        draft_version: draft_version_after_publish(row, version)
      },
      @publish_fields
    )
    |> validate_required([:published_version, :published_at])
  end

  @spec lifecycle_changeset(struct(), binary()) :: Ecto.Changeset.t()
  def lifecycle_changeset(%__MODULE__{} = row, lifecycle_state)
      when lifecycle_state in ["active", "archived"] do
    row
    |> cast(%{lifecycle_state: lifecycle_state}, @lifecycle_fields)
    |> validate_required([:lifecycle_state])
    |> validate_inclusion(:lifecycle_state, ["active", "archived"])
  end

  defp document_attrs(%Document{} = document, %__MODULE__{} = row) do
    version = Document.version(document)

    %{
      dashboard_id: document.dashboard_id,
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      name: document.name,
      description: document.description,
      document: JsonDocument.encode(Document.to_map(document)),
      latest_version: version,
      draft_version: version,
      lifecycle_state: row.lifecycle_state || "active"
    }
  end

  defp draft_version_after_publish(%__MODULE__{} = row, published_version) do
    latest_version = latest_version(row)

    cond do
      is_nil(latest_version) -> nil
      latest_version > published_version -> draft_version(row)
      true -> nil
    end
  end
end
