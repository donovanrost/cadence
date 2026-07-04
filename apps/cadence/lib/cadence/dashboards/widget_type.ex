defmodule Cadence.Dashboards.WidgetType do
  @moduledoc """
  Registry metadata for a dashboard widget type.
  """

  @type t :: %__MODULE__{
          widget_type_id: binary(),
          version: pos_integer(),
          name: binary(),
          category: atom(),
          icon: binary(),
          trust: :first_party,
          data_contract: map(),
          binding_schema: map(),
          options_schema: [map()],
          layout_contract: map(),
          drilldown_contract: map(),
          renderer: map()
        }

  defstruct [
    :widget_type_id,
    :version,
    :name,
    :category,
    :icon,
    :trust,
    :data_contract,
    :binding_schema,
    :options_schema,
    :layout_contract,
    :drilldown_contract,
    :renderer
  ]
end
