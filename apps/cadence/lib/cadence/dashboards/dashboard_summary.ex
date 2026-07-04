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
          widget_count: non_neg_integer(),
          document_version: pos_integer() | nil,
          latest_version: pos_integer() | nil,
          draft_version: pos_integer() | nil,
          published_version: pos_integer() | nil,
          published_at: DateTime.t() | nil,
          published_by: binary() | nil,
          lifecycle_state: binary()
        }

  defstruct [
    :dashboard_id,
    :organization_id,
    :mission_id,
    :name,
    :description,
    :document_version,
    :latest_version,
    :draft_version,
    :published_version,
    :published_at,
    :published_by,
    lifecycle_state: "active",
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
      widget_count: length(document.placements),
      document_version: document_version,
      latest_version: latest_version,
      draft_version: draft_version,
      published_version: get_attr(attrs, :published_version),
      published_at: get_attr(attrs, :published_at),
      published_by: get_attr(attrs, :published_by),
      lifecycle_state: get_attr(attrs, :lifecycle_state) || "active"
    }
  end

  defp get_attr(attrs, field), do: Map.get(attrs, field)

  defp attr_present?(attrs, field), do: Map.has_key?(attrs, field)
end
