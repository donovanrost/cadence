defmodule Cadence.Dashboards.WidgetType do
  @moduledoc """
  Registry metadata for a dashboard widget type.
  """

  @type t :: %__MODULE__{
          widget_type_id: binary(),
          version: pos_integer(),
          form_value: binary(),
          form_label: binary(),
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
    :form_value,
    :form_label,
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

  @spec validate(t()) :: :ok | {:error, :invalid_widget_type}
  def validate(%__MODULE__{} = widget_type) do
    with true <- valid_text?(widget_type.widget_type_id),
         true <- is_integer(widget_type.version) and widget_type.version > 0,
         true <- valid_text?(widget_type.form_value),
         true <- valid_text?(widget_type.form_label),
         true <- valid_text?(widget_type.name),
         true <- is_atom(widget_type.category) and not is_nil(widget_type.category),
         true <- valid_text?(widget_type.icon),
         true <- widget_type.trust == :first_party,
         true <- is_map(widget_type.data_contract),
         true <- is_map(widget_type.binding_schema),
         true <- is_list(widget_type.options_schema),
         true <- is_map(widget_type.layout_contract),
         true <- is_map(widget_type.drilldown_contract),
         true <- is_map(widget_type.renderer) do
      :ok
    else
      _invalid -> {:error, :invalid_widget_type}
    end
  end

  def validate(_widget_type), do: {:error, :invalid_widget_type}

  defp valid_text?(value), do: is_binary(value) and value != ""
end
