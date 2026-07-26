defmodule Cadence.Applications.SurfaceElements.Diagnostics do
  @moduledoc "Bounded exceptional findings rendered by the application host."

  alias Cadence.Applications.SurfaceElements.Diagnostic

  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          description: binary() | nil,
          items: [Diagnostic.t()],
          total_count: non_neg_integer()
        }

  @enforce_keys [:id, :title, :items, :total_count]
  defstruct [:id, :title, :description, :total_count, items: []]

  @max_items 20

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_diagnostics}
  def validate(%__MODULE__{} = diagnostics) do
    with true <- valid_text?(diagnostics.id),
         true <- valid_text?(diagnostics.title),
         true <- valid_description?(diagnostics.description),
         true <- is_list(diagnostics.items),
         true <- length(diagnostics.items) <= @max_items,
         true <- valid_total_count?(diagnostics),
         true <- Enum.all?(diagnostics.items, &valid_item?/1),
         true <- unique_item_ids?(diagnostics.items) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_diagnostics}
    end
  end

  defp valid_total_count?(diagnostics) do
    is_integer(diagnostics.total_count) and
      diagnostics.total_count >= length(diagnostics.items)
  end

  defp valid_item?(%Diagnostic{} = item) do
    valid_text?(item.id) and valid_text?(item.code) and
      item.severity in [:info, :warning, :error] and valid_text?(item.title) and
      valid_text?(item.detail) and valid_description?(item.value)
  end

  defp valid_item?(_item), do: false

  defp unique_item_ids?(items) do
    ids = Enum.map(items, & &1.id)
    length(Enum.uniq(ids)) == length(ids)
  end

  defp valid_text?(value), do: is_binary(value) and value != ""
  defp valid_description?(nil), do: true
  defp valid_description?(value), do: is_binary(value)
end
