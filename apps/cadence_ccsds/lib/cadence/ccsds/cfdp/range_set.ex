defmodule Cadence.CCSDS.CFDP.RangeSet do
  @moduledoc """
  Compact coverage ranges for externally stored CFDP file data.

  Ranges use an exclusive end offset and are normalized into sorted,
  non-overlapping intervals.
  """

  @type range :: {non_neg_integer(), non_neg_integer()}
  @type t :: [range()]

  @spec new() :: t()
  def new, do: []

  @spec put(t(), non_neg_integer(), non_neg_integer()) :: {:ok, t()} | {:error, term()}
  def put(ranges, offset, length)
      when is_list(ranges) and is_integer(offset) and offset >= 0 and is_integer(length) and
             length >= 0 do
    if length == 0 do
      {:ok, ranges}
    else
      ranges
      |> Kernel.++([{offset, offset + length}])
      |> Enum.sort()
      |> normalize([])
      |> then(&{:ok, &1})
    end
  end

  def put(_ranges, offset, length), do: {:error, {:invalid_file_range, offset, length}}

  @spec complete?(t(), non_neg_integer()) :: boolean()
  def complete?(_ranges, 0), do: true
  def complete?([{0, end_offset} | _rest], size), do: end_offset >= size
  def complete?(_ranges, _size), do: false

  @spec progress(t()) :: non_neg_integer()
  def progress([{0, end_offset} | _rest]), do: end_offset
  def progress(_ranges), do: 0

  @spec extent(t()) :: non_neg_integer()
  def extent([]), do: 0
  def extent(ranges), do: ranges |> List.last() |> elem(1)

  @spec missing(t(), non_neg_integer(), non_neg_integer()) :: [range()]
  def missing(ranges, start_offset, end_offset)
      when is_integer(start_offset) and is_integer(end_offset) and start_offset >= 0 and
             end_offset >= start_offset do
    ranges
    |> Enum.reduce({start_offset, []}, &advance_missing_cursor(&1, &2, end_offset))
    |> then(fn {cursor, gaps} ->
      gaps = if cursor < end_offset, do: [{cursor, end_offset} | gaps], else: gaps
      Enum.reverse(gaps)
    end)
  end

  defp normalize([], normalized), do: Enum.reverse(normalized)
  defp normalize([range | rest], []), do: normalize(rest, [range])

  defp normalize([{start_offset, end_offset} | rest], [{previous_start, previous_end} | tail])
       when start_offset <= previous_end do
    normalize(rest, [{previous_start, max(previous_end, end_offset)} | tail])
  end

  defp normalize([range | rest], normalized), do: normalize(rest, [range | normalized])

  defp advance_missing_cursor({start_offset, range_end}, {cursor, gaps}, end_offset) do
    cond do
      range_end <= cursor or start_offset >= end_offset ->
        {cursor, gaps}

      start_offset > cursor ->
        {min(range_end, end_offset), [{cursor, min(start_offset, end_offset)} | gaps]}

      true ->
        {max(cursor, min(range_end, end_offset)), gaps}
    end
  end
end
