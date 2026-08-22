defmodule CCSDS.CFDP.SegmentStore do
  @moduledoc """
  Pure, overlap-aware in-memory segment assembly used by the transaction
  procedures.

  Equal retransmissions are idempotent. Conflicting overlapping octets are
  rejected as invalid file structure.
  """

  @type segment :: {non_neg_integer(), binary()}
  @type t :: [segment()]

  @spec new() :: t()
  def new, do: []

  @spec put(t(), non_neg_integer(), binary()) :: {:ok, t()} | {:error, term()}
  def put(segments, offset, data)
      when is_list(segments) and is_integer(offset) and offset >= 0 and is_binary(data) do
    if data == <<>> do
      {:ok, segments}
    else
      segments
      |> Kernel.++([{offset, data}])
      |> Enum.sort_by(&elem(&1, 0))
      |> normalize([])
    end
  end

  def put(_segments, offset, data), do: {:error, {:invalid_file_segment, offset, data}}

  @spec complete?(t(), non_neg_integer()) :: boolean()
  def complete?(_segments, 0), do: true

  def complete?([{0, data} | _rest], size) when is_integer(size) and size > 0,
    do: byte_size(data) >= size

  def complete?(_segments, _size), do: false

  @spec assemble(t(), non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def assemble(_segments, 0), do: {:ok, <<>>}

  def assemble([{0, data} | _rest], size) when byte_size(data) >= size,
    do: {:ok, binary_part(data, 0, size)}

  def assemble(segments, size), do: {:error, {:incomplete_file, missing(segments, 0, size)}}

  @spec progress(t()) :: non_neg_integer()
  def progress([{0, data} | _rest]), do: byte_size(data)
  def progress(_segments), do: 0

  @spec extent(t()) :: non_neg_integer()
  def extent([]), do: 0

  def extent(segments),
    do: segments |> List.last() |> then(fn {offset, data} -> offset + byte_size(data) end)

  @spec missing(t(), non_neg_integer(), non_neg_integer()) ::
          [{non_neg_integer(), non_neg_integer()}]
  def missing(segments, start_offset, end_offset)
      when is_list(segments) and is_integer(start_offset) and is_integer(end_offset) and
             start_offset >= 0 and end_offset >= start_offset do
    segments
    |> Enum.reduce({start_offset, []}, &advance_missing_cursor(&1, &2, end_offset))
    |> then(fn {cursor, gaps} ->
      gaps = if cursor < end_offset, do: [{cursor, end_offset} | gaps], else: gaps
      Enum.reverse(gaps)
    end)
  end

  defp advance_missing_cursor({offset, data}, {cursor, gaps}, end_offset) do
    segment_end = offset + byte_size(data)

    cond do
      segment_end <= cursor or offset >= end_offset ->
        {cursor, gaps}

      offset > cursor ->
        next_cursor = max(cursor, min(segment_end, end_offset))
        {next_cursor, [{cursor, min(offset, end_offset)} | gaps]}

      true ->
        {max(cursor, min(segment_end, end_offset)), gaps}
    end
  end

  defp normalize([], normalized), do: {:ok, Enum.reverse(normalized)}
  defp normalize([segment | rest], []), do: normalize(rest, [segment])

  defp normalize([{offset, data} = current | rest], [{previous_offset, previous_data} | tail]) do
    previous_end = previous_offset + byte_size(previous_data)

    if offset > previous_end do
      normalize(rest, [current, {previous_offset, previous_data} | tail])
    else
      overlap = previous_end - offset
      comparable = min(overlap, byte_size(data))
      previous_overlap = binary_part(previous_data, offset - previous_offset, comparable)
      current_overlap = binary_part(data, 0, comparable)

      if previous_overlap == current_overlap do
        extension = binary_part(data, comparable, byte_size(data) - comparable)
        normalize(rest, [{previous_offset, previous_data <> extension} | tail])
      else
        {:error, {:conflicting_file_segment, offset, comparable}}
      end
    end
  end
end
