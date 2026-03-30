defmodule Cadence.Runtime.Clock do
  @moduledoc """
  Explicit runtime clock used by live and replay execution paths.
  """

  @type mode :: :live | :replay

  @type t :: %__MODULE__{
          mode: mode(),
          current_time: DateTime.t()
        }

  defstruct [:mode, :current_time]

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      mode: Keyword.get(opts, :mode, :live),
      current_time: Keyword.get(opts, :current_time, DateTime.utc_now())
    }
  end

  @spec live?(t()) :: boolean()
  def live?(%__MODULE__{mode: :live}), do: true
  def live?(%__MODULE__{}), do: false

  @spec replay?(t()) :: boolean()
  def replay?(%__MODULE__{mode: :replay}), do: true
  def replay?(%__MODULE__{}), do: false

  @spec advance_to(t(), DateTime.t()) :: t()
  def advance_to(%__MODULE__{} = clock, %DateTime{} = target_time) do
    case DateTime.compare(target_time, clock.current_time) do
      :lt -> clock
      _comparison -> %{clock | current_time: target_time}
    end
  end

  @spec set_current_time(t(), DateTime.t()) :: t()
  def set_current_time(%__MODULE__{} = clock, %DateTime{} = current_time) do
    %{clock | current_time: current_time}
  end
end
