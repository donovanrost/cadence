defmodule Cadence.SemanticRuntime.Update do
  @moduledoc "One parameter update flowing through the ordered semantic engine."

  @type quality :: :good | :suspect | :bad | :unknown

  @type t :: %__MODULE__{
          update_id: binary(),
          parameter_id: binary(),
          qualified_name: binary(),
          value: term(),
          raw_value: term(),
          quality: quality(),
          generation_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          producer_kind: atom(),
          producer_id: binary(),
          source_update_ids: [binary()],
          metadata: map()
        }

  @enforce_keys [
    :update_id,
    :parameter_id,
    :qualified_name,
    :value,
    :quality,
    :receipt_time,
    :producer_kind,
    :producer_id
  ]
  defstruct @enforce_keys ++ [:raw_value, :generation_time, source_update_ids: [], metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)
end
