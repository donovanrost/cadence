defmodule Cadence.Dashboards.Section do
  @moduledoc """
  A collapsible operational group in a dashboard document.

  Sections organize placements without changing their data or scope semantics.
  """

  @type t :: %__MODULE__{
          section_id: binary(),
          title: binary(),
          description: binary() | nil,
          collapsed_by_default?: boolean()
        }

  defstruct [:section_id, :title, :description, collapsed_by_default?: false]

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      section_id: get_attr(attrs, :section_id),
      title: get_attr(attrs, :title),
      description: get_attr(attrs, :description),
      collapsed_by_default?: get_attr(attrs, :collapsed_by_default?) == true
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = section) do
    %{
      section_id: section.section_id,
      title: section.title,
      description: section.description,
      collapsed_by_default?: section.collapsed_by_default?
    }
  end

  defp get_attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
