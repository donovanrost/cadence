defmodule Cadence.Observability.AsyncContext do
  @moduledoc """
  Trace context and enqueue timestamp carried across an asynchronous boundary.
  """

  alias Cadence.Observability

  @type t :: %__MODULE__{
          parent_context: OpenTelemetry.Ctx.t(),
          enqueued_at: integer()
        }

  defstruct [:parent_context, :enqueued_at]

  @spec capture() :: t()
  def capture do
    %__MODULE__{
      parent_context: Observability.current_context(),
      enqueued_at: System.monotonic_time()
    }
  end

  @spec queue_wait_ms(t()) :: float()
  def queue_wait_ms(%__MODULE__{enqueued_at: enqueued_at}) when is_integer(enqueued_at) do
    System.monotonic_time()
    |> Kernel.-(enqueued_at)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
