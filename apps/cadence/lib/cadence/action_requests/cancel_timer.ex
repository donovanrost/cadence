defmodule Cadence.ActionRequests.CancelTimer do
  @moduledoc """
  Requests that the partition runtime cancel a managed-application timer.
  """

  @type t :: %__MODULE__{
          timer_key: binary()
        }

  defstruct [:timer_key]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      timer_key: Map.fetch!(attrs, :timer_key)
    }
  end
end
