defmodule Cadence.Observability.Metrics.Definition do
  @moduledoc false

  @enforce_keys [:name, :type, :description, :unit, :attributes]
  defstruct [
    :name,
    :type,
    :description,
    :unit,
    :event_name,
    :measurement,
    attributes: [],
    buckets: [],
    keep: nil,
    tag_values: nil
  ]

  @type metric_type :: :counter | :gauge | :histogram | :up_down_counter

  @type t :: %__MODULE__{
          name: binary(),
          type: metric_type(),
          description: binary(),
          unit: binary(),
          event_name: [atom()] | nil,
          measurement: atom() | (map(), map() -> number()) | nil,
          attributes: [binary()],
          buckets: [number()],
          keep: (map(), map() -> boolean()) | nil,
          tag_values: (map() -> map()) | nil
        }
end
