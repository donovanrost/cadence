defmodule Cadence.Reads.SampleOrigin do
  @moduledoc """
  Where a stored sample's packet came from (#1078 P5 slice E1a), for the sample's details.

  The observation row carries no origin (it gains nothing in E1a), so it is read back from the
  archived packet the sample came from: one lookup on `packet_id` for the whole page of samples,
  never one per row (`RecordArchive.fetch_packet_origins/2`). A derived sample has no packet of its
  own, but it carries its trigger's packet id, so the same lookup serves it.

  Never a guess. Each sample answers `%{origin: map | nil, origin_reason: nil | reason}`:

    * `nil` reason: the archived packet's origin descriptor, as JSON values;
    * `"packet_not_archived"`: the packet is no longer in the protocol archive (its retention
      ended, or it never was archived) while the observation still exists;
    * `"origin_not_recorded"`: the packet was archived before origins were recorded;
    * `"timer_triggered"`: a derived value a timer produced, so there is no packet;
    * `"archive_unavailable"`: the archive could not be read now.
  """

  alias Cadence.Protocol.{Origin, RecordArchive}

  @derived_prefix "mission_model_algorithm:"

  @type sample :: %{
          required(:sample_id) => binary(),
          required(:packet_id) => binary() | nil,
          required(:packet_definition_id) => binary() | nil
        }
  @type answer :: %{origin: map() | nil, origin_reason: binary() | nil}

  @doc """
  The answers for a page of samples, by sample id; one archive lookup for the page. `opts[:archive]`
  is the protocol archive policy to read (the configured one by default).
  """
  @spec for_samples(binary(), [sample()], keyword()) :: %{binary() => answer()}
  def for_samples(mission_id, samples, opts \\ [])
      when is_binary(mission_id) and is_list(samples) do
    {timer, packeted} = Enum.split_with(samples, &timer_triggered?/1)

    ids =
      packeted
      |> Enum.map(& &1.packet_id)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    origins = lookup(Keyword.get(opts, :archive), mission_id, ids)

    timer_answers = Map.new(timer, &{&1.sample_id, reason("timer_triggered")})

    packeted
    |> Map.new(&{&1.sample_id, answer(origins, &1.packet_id)})
    |> Map.merge(timer_answers)
  end

  @doc "The answer for one sample."
  @spec for_sample(binary(), sample(), keyword()) :: answer()
  def for_sample(mission_id, sample, opts \\ []) do
    mission_id |> for_samples([sample], opts) |> Map.fetch!(sample.sample_id)
  end

  # A derived value has no packet when a timer produced it: its packet id is its own update id.
  defp timer_triggered?(%{
         packet_definition_id: @derived_prefix <> _,
         packet_id: id,
         sample_id: id
       }),
       do: true

  defp timer_triggered?(_sample), do: false

  defp lookup(_policy, _mission_id, []), do: {:ok, %{}}
  defp lookup(nil, mission_id, ids), do: RecordArchive.fetch_packet_origins(mission_id, ids)

  defp lookup(policy, mission_id, ids),
    do: RecordArchive.fetch_packet_origins(policy, mission_id, ids)

  defp answer({:error, _reason}, _packet_id), do: reason("archive_unavailable")
  defp answer({:ok, _origins}, nil), do: reason("packet_not_archived")

  defp answer({:ok, origins}, packet_id) do
    case Map.fetch(origins, packet_id) do
      {:ok, %{} = origin} -> %{origin: Origin.to_json(origin), origin_reason: nil}
      {:ok, nil} -> reason("origin_not_recorded")
      :error -> reason("packet_not_archived")
    end
  end

  defp reason(reason), do: %{origin: nil, origin_reason: reason}
end
