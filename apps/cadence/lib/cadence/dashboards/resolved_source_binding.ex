defmodule Cadence.Dashboards.ResolvedSourceBinding do
  @moduledoc """
  Concrete source binding selected for a planned dashboard source request.
  """

  alias Cadence.DataSources.{DataBinding, DataBindingInterval, DataSource}

  @type t :: %__MODULE__{
          binding: DataBinding.t(),
          binding_interval: DataBindingInterval.t() | nil,
          segment_from: DateTime.t() | nil,
          segment_to: DateTime.t() | nil,
          data_source: DataSource.t(),
          realm: atom() | binary(),
          dataset: binary() | nil,
          source_selection: map()
        }

  defstruct [
    :binding,
    :binding_interval,
    :segment_from,
    :segment_to,
    :data_source,
    :realm,
    :dataset,
    source_selection: %{}
  ]
end
