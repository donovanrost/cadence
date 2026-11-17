defmodule Cadence.Platform.ReplayId do
  @moduledoc """
  Replay-safe ids for monitoring effects (DECISIONS #99; docs/apogee/domain/
  context-deltas-and-replay-ids.md). An effect replayed after a crash gets the same id as the first
  time, so it is written insert-or-get instead of twice.

      <kind>_<receipt µs, 10><stream ordinal, 6><offset, 8><index, 3>     e.g. aep_65ahf2ggn6000k3v0000a3f1000

  Every field is fixed-width base32hex (`0-9a-v`), so under C collation the ids sort like the
  numbers: time first, so inserts from every stream append at the index's right edge.

  - receipt: the input frame's receipt time, µs since 2020-01-01 (2^50 µs ≈ 35 years);
  - stream ordinal: allocated per (partition, journal stream), never hashed, so two streams can't
    share one (`partition_stream_keys`); timers and partition init have their own ordinals;
  - offset: the input frame's absolute journal offset (2^40 bytes per stream);
  - index: the effect's position among that input's effects of this kind in this partition
    (< 32,768: a frame's monitoring evaluations, every monitored update x policy, fit; past it an
    effect keeps an `Ids.new` id, counted as `[:cadence, :replay_id, :index_overflow]`).
  """

  require Logger

  @alphabet ~c"0123456789abcdefghijklmnopqrstuv"
  @epoch_us DateTime.to_unix(~U[2020-01-01 00:00:00Z], :microsecond)

  @kinds %{managed_action_request: "mar", alarm_episode: "aep", alarm_event: "aev"}
  @widths [receipt: 10, ordinal: 6, offset: 8, index: 3]
  @max_index 32 * 32 * 32

  @type kind :: :managed_action_request | :alarm_episode | :alarm_event
  @type key :: %{
          receipt: DateTime.t(),
          ordinal: non_neg_integer(),
          offset: non_neg_integer(),
          index: non_neg_integer()
        }

  @doc "The id of a `kind` effect with this key."
  @spec id(kind(), key()) :: binary()
  def id(kind, %{receipt: %DateTime{} = receipt, ordinal: ordinal, offset: offset, index: index}) do
    Map.fetch!(@kinds, kind) <>
      "_" <>
      encode(DateTime.to_unix(receipt, :microsecond) - @epoch_us, :receipt) <>
      encode(ordinal, :ordinal) <> encode(offset, :offset) <> encode(index, :index)
  end

  @typedoc "What an effect's id derives from: `[stream key, offset, receipt µs since the Unix epoch]`."
  @type source :: [term()]

  @doc """
  Numbers `items` per source (stream key, offset), in list order, and gives each its key:
  `[{item, key | nil}]`. `source_of` gives an item's source or nil; `ordinals` maps stream keys to
  their allocated ordinals. An item without a source, or whose stream has no ordinal, gets nil
  (it keeps an `Ids.new` id). The order of one input's effects must be deterministic: the same
  input numbered again (a replay) must give the same keys.
  """
  @spec number([item], (item -> source() | nil), %{optional(binary()) => pos_integer()}) ::
          [{item, key() | nil}]
        when item: term()
  def number(items, source_of, ordinals) do
    {numbered, _counters} =
      Enum.map_reduce(items, %{}, fn item, counters ->
        case source_of.(item) do
          [stream, offset, receipt_us]
          when is_map_key(ordinals, stream) and is_integer(offset) and is_integer(receipt_us) ->
            index = Map.get(counters, {stream, offset}, 0)
            counters = Map.put(counters, {stream, offset}, index + 1)
            {{item, key(receipt_us, Map.fetch!(ordinals, stream), offset, index)}, counters}

          _no_source ->
            {{item, nil}, counters}
        end
      end)

    numbered
  end

  # An input with more than @max_index effects of one kind can't number them all: those past it
  # keep an Ids.new id (not replay-safe) with a warning, rather than crashing the partition.
  defp key(receipt_us, ordinal, offset, index) when index < @max_index,
    do: %{
      receipt: DateTime.from_unix!(receipt_us, :microsecond),
      ordinal: ordinal,
      offset: offset,
      index: index
    }

  defp key(_receipt_us, ordinal, offset, index) do
    :telemetry.execute([:cadence, :replay_id, :index_overflow], %{count: 1}, %{
      ordinal: ordinal,
      offset: offset
    })

    if index == @max_index do
      Logger.warning(
        "MM_REPLAY_ID_INDEX_OVERFLOW: more than #{@max_index} effects for one input (ordinal " <>
          "#{ordinal}, offset #{offset}); the rest keep non-replay-safe ids, each counted as " <>
          "[:cadence, :replay_id, :index_overflow]"
      )
    end

    nil
  end

  @doc "The stream keys of the sources among `sources` (nils skipped), once each."
  @spec stream_keys([source() | nil]) :: [binary()]
  def stream_keys(sources) do
    for [stream, _offset, _receipt] <- sources, is_binary(stream), uniq: true, do: stream
  end

  @doc """
  The tripwire (the director's condition 1): an effect whose replay-safe id is already stored must
  be the same effect, compared on what derives from its input. `stored` and `new` are those fields;
  equal means an honest replay (`:ok`), anything else is a bug that is logged as
  `MM_REPLAY_ID_CONFLICT` and returned as an error, never swallowed.
  """
  @spec check_replay(kind(), binary(), map(), map()) ::
          :ok | {:error, {:replay_id_conflict, kind(), binary()}}
  def check_replay(kind, id, stored, new) do
    if comparable(stored) == comparable(new) do
      :ok
    else
      Logger.error(
        "MM_REPLAY_ID_CONFLICT #{kind} #{id}: a different effect already holds this id " <>
          "(stored #{inspect(stored)}, new #{inspect(new)})"
      )

      {:error, {:replay_id_conflict, kind, id}}
    end
  end

  # Stored rows come back JSON-decoded; compare both sides in that form.
  defp comparable(fields), do: fields |> Jason.encode!() |> Jason.decode!()

  @doc "The parts of an id this module built; `:error` for any other id (e.g. `Ids.new`)."
  @spec parse(binary()) ::
          {:ok,
           %{
             kind: kind(),
             receipt_us: integer(),
             ordinal: integer(),
             offset: integer(),
             index: integer()
           }}
          | :error
  def parse(<<prefix::binary-size(3), "_", body::binary-size(27)>>) do
    with {:ok, kind} <- kind(prefix),
         <<receipt::binary-size(10), ordinal::binary-size(6), offset::binary-size(8),
           index::binary-size(3)>> <- body,
         {:ok, receipt} <- decode(receipt),
         {:ok, ordinal} <- decode(ordinal),
         {:ok, offset} <- decode(offset),
         {:ok, index} <- decode(index) do
      {:ok,
       %{
         kind: kind,
         receipt_us: receipt + @epoch_us,
         ordinal: ordinal,
         offset: offset,
         index: index
       }}
    else
      _other -> :error
    end
  end

  def parse(_id), do: :error

  defp kind(prefix) do
    case Enum.find(@kinds, fn {_kind, value} -> value == prefix end) do
      {kind, _prefix} -> {:ok, kind}
      nil -> :error
    end
  end

  defp encode(value, field) when is_integer(value) and value >= 0 do
    width = Keyword.fetch!(@widths, field)

    if value >= Integer.pow(32, width) do
      raise ArgumentError, "#{field} #{value} doesn't fit #{width} base32hex digits"
    end

    value
    |> digits([])
    |> List.to_string()
    |> String.pad_leading(width, "0")
  end

  defp encode(value, field),
    do: raise(ArgumentError, "#{field} must be a non-negative integer, got: #{inspect(value)}")

  defp digits(value, acc) when value < 32, do: [Enum.at(@alphabet, value) | acc]

  defp digits(value, acc),
    do: digits(div(value, 32), [Enum.at(@alphabet, rem(value, 32)) | acc])

  defp decode(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce_while({:ok, 0}, fn char, {:ok, acc} ->
      case Enum.find_index(@alphabet, &(&1 == char)) do
        nil -> {:halt, :error}
        digit -> {:cont, {:ok, acc * 32 + digit}}
      end
    end)
  end
end
