defmodule Cadence.Runtime.DownlinkCombiner do
  @moduledoc """
  Contact-level combiner for duplicate downlink observations contributed by
  multiple active downlink paths.
  """

  use GenServer

  alias Cadence.Contacts.{
    CombinedDownlinkRecord,
    DownlinkDiagnostic,
    DownlinkObservation
  }

  alias Cadence.Persistence
  alias Cadence.Runtime.ContactPathSpec
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  @type state :: %{
          mission_id: binary(),
          realized_contact_id: binary(),
          selected_downlink_path_id: binary() | nil,
          current_winners: %{required(binary()) => DownlinkObservation.t()},
          observation_count: non_neg_integer(),
          combined_record_count: non_neg_integer(),
          diagnostic_count: non_neg_integer()
        }

  def start_link(opts) when is_list(opts) do
    %RealizedContactRuntimeSpec{} = realized_contact = Keyword.fetch!(opts, :realized_contact)

    GenServer.start_link(
      __MODULE__,
      opts,
      name:
        MissionRuntime.downlink_combiner_name(
          realized_contact.mission_id,
          realized_contact.realized_contact_id
        )
    )
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(downlink_combiner) do
    GenServer.call(downlink_combiner, :snapshot)
  end

  @spec handle_observation(pid(), DownlinkObservation.t()) :: {:ok, [term()]} | {:error, term()}
  def handle_observation(downlink_combiner, %DownlinkObservation{} = observation) do
    GenServer.call(downlink_combiner, {:handle_observation, observation})
  end

  @impl true
  def init(opts) do
    %RealizedContactRuntimeSpec{} = realized_contact = Keyword.fetch!(opts, :realized_contact)

    {:ok,
     %{
       mission_id: realized_contact.mission_id,
       realized_contact_id: realized_contact.realized_contact_id,
       selected_downlink_path_id: selected_downlink_path_id(realized_contact.paths),
       current_winners: %{},
       observation_count: 0,
       combined_record_count: 0,
       diagnostic_count: 0
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    current_winners =
      state.current_winners
      |> Enum.sort_by(fn {observation_key, _observation} -> observation_key end)
      |> Enum.map(fn {observation_key, observation} ->
        %{
          observation_key: observation_key,
          path_id: observation.path_id,
          observation_id: observation.observation_id,
          source_endpoint_ref: observation.source_endpoint_ref,
          observed_at: observation.observed_at,
          quality_score: observation.quality_score
        }
      end)

    {:reply,
     {:ok,
      %{
        mission_id: state.mission_id,
        realized_contact_id: state.realized_contact_id,
        selected_downlink_path_id: state.selected_downlink_path_id,
        observation_count: state.observation_count,
        combined_record_count: state.combined_record_count,
        diagnostic_count: state.diagnostic_count,
        active_observation_key_count: map_size(state.current_winners),
        current_winners: current_winners
      }}, state}
  end

  def handle_call({:handle_observation, %DownlinkObservation{} = observation}, _from, state) do
    current_winner = Map.get(state.current_winners, observation.observation_key)

    {winner, diagnostic_kind, emit_combined?, competing_observation_id} =
      select_winner(
        current_winner,
        observation,
        state.selected_downlink_path_id
      )

    combined_records =
      if emit_combined? do
        [
          CombinedDownlinkRecord.new(%{
            mission_id: state.mission_id,
            realized_contact_id: state.realized_contact_id,
            observation_key: observation.observation_key,
            source_endpoint_ref: winner.source_endpoint_ref,
            selected_path_id: winner.path_id,
            selected_observation_id: winner.observation_id,
            payload: winner.payload,
            selected_reason: diagnostic_kind,
            observed_at: winner.observed_at,
            metadata: %{quality_score: winner.quality_score}
          })
        ]
      else
        []
      end

    diagnostics = [
      DownlinkDiagnostic.new(%{
        mission_id: state.mission_id,
        realized_contact_id: state.realized_contact_id,
        observation_key: observation.observation_key,
        path_id: observation.path_id,
        selected_path_id: winner.path_id,
        observation_id: observation.observation_id,
        competing_observation_id: competing_observation_id,
        diagnostic_kind: diagnostic_kind,
        recorded_at: observation.observed_at,
        metadata: %{
          selected_observation_id: winner.observation_id,
          selected_quality_score: winner.quality_score,
          observation_quality_score: observation.quality_score
        }
      })
    ]

    case Persistence.persist_downlink_combiner_records(
           [observation],
           combined_records,
           diagnostics
         ) do
      :ok ->
        next_state =
          state
          |> Map.put(
            :current_winners,
            Map.put(state.current_winners, observation.observation_key, winner)
          )
          |> Map.update!(:observation_count, &(&1 + 1))
          |> Map.update!(:combined_record_count, &(&1 + length(combined_records)))
          |> Map.update!(:diagnostic_count, &(&1 + 1))

        {:reply, {:ok, [observation] ++ combined_records ++ diagnostics}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp selected_downlink_path_id(paths) do
    paths
    |> Enum.find(fn %ContactPathSpec{} = path ->
      path.direction == :downlink and path.selection_role == :selected
    end)
    |> case do
      %ContactPathSpec{} = path -> path.path_id
      nil -> nil
    end
  end

  defp select_winner(nil, %DownlinkObservation{} = observation, _selected_downlink_path_id) do
    {observation, :accepted, true, nil}
  end

  defp select_winner(
         %DownlinkObservation{} = current_winner,
         %DownlinkObservation{} = observation,
         selected_downlink_path_id
       ) do
    cond do
      selected_downlink_path_id == observation.path_id and
          selected_downlink_path_id != current_winner.path_id ->
        {observation, :selected_path_preferred, true, current_winner.observation_id}

      selected_downlink_path_id == current_winner.path_id and
          selected_downlink_path_id != observation.path_id ->
        {current_winner, :existing_selection_retained, false, current_winner.observation_id}

      observation.quality_score > current_winner.quality_score ->
        {observation, :higher_quality_preferred, true, current_winner.observation_id}

      true ->
        {current_winner, :existing_selection_retained, false, current_winner.observation_id}
    end
  end
end
