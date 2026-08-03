defmodule Cadence.Dashboards.DashboardSummary do
  @moduledoc """
  Lightweight dashboard read model for navigation and listing surfaces.
  """

  alias Cadence.Dashboards.Document

  @type t :: %__MODULE__{
          dashboard_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          name: binary(),
          description: binary() | nil,
          tags: [binary()],
          widget_count: non_neg_integer(),
          document_version: pos_integer() | nil,
          latest_version: pos_integer() | nil,
          draft_version: pos_integer() | nil,
          published_version: pos_integer() | nil,
          published_at: DateTime.t() | nil,
          published_by: binary() | nil,
          lifecycle_state: binary(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :dashboard_id,
    :organization_id,
    :mission_id,
    :name,
    :description,
    :inserted_at,
    :updated_at,
    :document_version,
    :latest_version,
    :draft_version,
    :published_version,
    :published_at,
    :published_by,
    lifecycle_state: "active",
    tags: [],
    widget_count: 0
  ]

  @spec from_document(Document.t()) :: t()
  def from_document(%Document{} = document), do: from_document(document, %{})

  @spec from_document(Document.t(), map() | struct()) :: t()
  def from_document(%Document{} = document, attrs) when is_map(attrs) do
    document_version = Document.version(document)
    latest_version = get_attr(attrs, :latest_version) || document_version

    draft_version =
      if attr_present?(attrs, :draft_version),
        do: get_attr(attrs, :draft_version),
        else: latest_version

    %__MODULE__{
      dashboard_id: document.dashboard_id,
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      name: document.name,
      description: document.description,
      tags: document_tags(document),
      widget_count: length(document.placements),
      document_version: document_version,
      latest_version: latest_version,
      draft_version: draft_version,
      published_version: get_attr(attrs, :published_version),
      published_at: get_attr(attrs, :published_at),
      published_by: get_attr(attrs, :published_by),
      lifecycle_state: get_attr(attrs, :lifecycle_state) || "active",
      inserted_at: get_attr(attrs, :inserted_at),
      updated_at: get_attr(attrs, :updated_at)
    }
  end

  defp document_tags(%Document{metadata: metadata}) when is_map(metadata) do
    metadata
    |> get_attr(:tags)
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp document_tags(%Document{}), do: []

  defp get_attr(attrs, field), do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field)))

  defp attr_present?(attrs, field), do: Map.has_key?(attrs, field)
end
