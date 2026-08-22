defmodule Cadence.Extensions.WidgetTypeContribution do
  @moduledoc "A typed package contribution referencing one dashboard widget-type version."

  @type t :: %__MODULE__{
          widget_type_id: binary(),
          widget_type_version: pos_integer()
        }

  @enforce_keys [:widget_type_id, :widget_type_version]
  defstruct [:widget_type_id, :widget_type_version]

  @spec validate(t()) :: :ok | {:error, :invalid_widget_type_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_binary(contribution.widget_type_id) and contribution.widget_type_id != "" and
         is_integer(contribution.widget_type_version) and contribution.widget_type_version > 0 do
      :ok
    else
      {:error, :invalid_widget_type_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_widget_type_contribution}
end
