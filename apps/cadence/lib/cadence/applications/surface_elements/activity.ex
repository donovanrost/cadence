defmodule Cadence.Applications.SurfaceElements.Activity do
  @moduledoc "Host-rendered operational activity projection with bounded typed items."

  alias Cadence.Applications.SurfaceElements.ActivityItem

  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          description: binary() | nil,
          items: [ActivityItem.t()],
          empty_title: binary(),
          empty_description: binary() | nil
        }

  @enforce_keys [:id, :title, :items, :empty_title]
  defstruct [:id, :title, :description, :empty_title, :empty_description, items: []]

  @max_items 20

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_activity}
  def validate(%__MODULE__{} = activity) do
    with true <- valid_text?(activity.id),
         true <- valid_text?(activity.title),
         true <- optional_text?(activity.description),
         true <- valid_text?(activity.empty_title),
         true <- optional_text?(activity.empty_description),
         true <- is_list(activity.items),
         true <- length(activity.items) <= @max_items,
         true <- Enum.all?(activity.items, &valid_item?/1),
         true <- unique_item_ids?(activity.items) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_activity}
    end
  end

  def validate(_activity), do: {:error, :invalid_application_surface_activity}

  defp valid_item?(%ActivityItem{} = item) do
    valid_text?(item.id) and valid_text?(item.title) and valid_text?(item.detail) and
      optional_text?(item.value) and optional_text?(item.timestamp) and
      item.tone in [:ready, :attention, :blocked, :info]
  end

  defp valid_item?(_item), do: false

  defp unique_item_ids?(items) do
    ids = Enum.map(items, & &1.id)
    length(Enum.uniq(ids)) == length(ids)
  end

  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
