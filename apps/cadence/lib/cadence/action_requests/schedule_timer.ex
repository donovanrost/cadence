defmodule Cadence.ActionRequests.ScheduleTimer do
  @moduledoc """
  Requests that the partition runtime schedule a one-shot managed-application
  timer.
  """

  @type t :: %__MODULE__{
          timer_key: binary(),
          delay_ms: pos_integer(),
          metadata: map()
        }

  defstruct [:timer_key, :delay_ms, metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      timer_key: Map.fetch!(attrs, :timer_key),
      delay_ms: Map.fetch!(attrs, :delay_ms),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
