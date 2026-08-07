defmodule Cadence.Dashboards.AnnotationSpan do
  @moduledoc """
  Time geometry for a dashboard annotation.

  Domain adapters describe an annotation as either a point or an interval. The
  renderer decides how that geometry is presented and clipped to a chart.
  """

  alias Cadence.Platform.ContractNormalization

  @kinds [:point, :interval]

  @type t :: %__MODULE__{
          kind: :point | :interval,
          starts_at: DateTime.t(),
          ends_at: DateTime.t() | nil
        }

  defstruct [:kind, :starts_at, :ends_at]

  @spec kinds() :: [:point | :interval]
  def kinds, do: @kinds

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t() | nil
  def normalize(%__MODULE__{} = span) do
    %__MODULE__{
      kind: normalize_kind(span.kind, span.ends_at),
      starts_at: normalize_datetime(span.starts_at),
      ends_at: normalize_datetime(span.ends_at)
    }
  end

  def normalize(span) when is_map(span) do
    ends_at = span |> ContractNormalization.attr(:ends_at) |> normalize_datetime()

    %__MODULE__{
      kind:
        span
        |> ContractNormalization.attr(:kind)
        |> normalize_kind(ends_at),
      starts_at:
        span
        |> ContractNormalization.attr(:starts_at)
        |> normalize_datetime(),
      ends_at: ends_at
    }
  end

  def normalize(_span), do: nil

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{kind: :point, starts_at: %DateTime{}, ends_at: nil}), do: true

  def valid?(%__MODULE__{
        kind: :interval,
        starts_at: %DateTime{},
        ends_at: nil
      }),
      do: true

  def valid?(%__MODULE__{
        kind: :interval,
        starts_at: %DateTime{} = starts_at,
        ends_at: %DateTime{} = ends_at
      }),
      do: DateTime.compare(starts_at, ends_at) in [:lt, :eq]

  def valid?(%__MODULE__{}), do: false

  defp normalize_kind(nil, nil), do: :point
  defp normalize_kind(nil, %DateTime{}), do: :interval

  defp normalize_kind(kind, _ends_at),
    do: ContractNormalization.known_atom(kind, @kinds)

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp normalize_datetime(_value), do: nil
end
