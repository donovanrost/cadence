defmodule Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour do
  @moduledoc """
  Common behaviour and boilerplate for pipeline stages.

  Each stage in the V2 pipeline is a GenStage producer-consumer that:
  - Receives events from upstream
  - Processes them via the `process/2` callback
  - Emits events downstream
  - Records timing via Stats module

  ## Usage

      defmodule MyStage do
        use Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour

        @impl true
        def stage_name, do: :my_stage

        @impl true
        def process(event, state) do
          # Do processing...
          {:ok, updated_event}
        end
      end

  ## Callbacks

  - `stage_name/0` - Returns atom identifying this stage for timing/logging
  - `process/2` - Processes a single event, returns {:ok, event} or {:error, reason}
  - `init_state/1` (optional) - Additional state initialization

  ## Error Handling

  If `process/2` returns `{:error, reason}`, the event is dropped and
  an error is logged. Failed events don't propagate downstream.
  """

  @doc """
  Returns the atom name of this stage (e.g., :identify, :decom).
  Used for timing instrumentation and logging.
  """
  @callback stage_name() :: atom()

  @doc """
  Processes a single PipelineEvent.

  ## Parameters

  - `event` - The PipelineEvent to process
  - `state` - Current stage state (contains mission_id, partition, etc.)

  ## Returns

  - `{:ok, updated_event}` - Successfully processed event
  - `{:skip, reason}` - Skip this event (e.g., unknown packet type)
  - `{:error, reason}` - Processing failed, event will be dropped
  """
  @callback process(
              event :: Cadence.Runtime.Telemetry.PipelineV2.PipelineEvent.t(),
              state :: map()
            ) ::
              {:ok, Cadence.Runtime.Telemetry.PipelineV2.PipelineEvent.t()}
              | {:skip, term()}
              | {:error, term()}

  @doc """
  Optional callback for additional state initialization.
  Called during GenStage init with the opts map.
  Return a map to merge into the default state.
  """
  @callback init_state(opts :: map()) :: map()

  @optional_callbacks [init_state: 1]

  defmacro __using__(_opts) do
    quote do
      use GenStage
      require Logger

      @behaviour Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour

      alias Cadence.Runtime.Telemetry.PipelineV2.PipelineEvent
      alias Cadence.Telemetry.Stats

      # Increased defaults for high-throughput telemetry (was 10/5)
      @default_max_demand 500
      @default_min_demand 250
      # Stats sampling: record 1 in N events to reduce ETS overhead
      @timing_sample_rate 100

      @doc false
      def start_link(opts) do
        name = Keyword.get(opts, :name)
        GenStage.start_link(__MODULE__, opts, name: name)
      end

      @impl GenStage
      def init(opts) do
        mission_id = Keyword.fetch!(opts, :mission_id)
        partition = Keyword.fetch!(opts, :partition)
        upstream = Keyword.get(opts, :upstream)
        # If upstream uses PartitionDispatcher, we need to specify our partition
        upstream_partitioned = Keyword.get(opts, :upstream_partitioned, false)

        # Configurable demand settings (can be passed from supervisor)
        max_demand = Keyword.get(opts, :max_demand, @default_max_demand)
        min_demand = Keyword.get(opts, :min_demand, @default_min_demand)

        base_state = %{
          mission_id: mission_id,
          partition: partition,
          stage_name: stage_name()
        }

        # Allow stages to add custom state via overridable init_state/1
        custom_state = init_state(opts)
        state = Map.merge(base_state, custom_state)

        # If upstream is provided, subscribe to it
        subscriptions =
          if upstream do
            sub_opts = [max_demand: max_demand, min_demand: min_demand]
            # Add partition option if upstream uses PartitionDispatcher
            sub_opts =
              if upstream_partitioned, do: [{:partition, partition} | sub_opts], else: sub_opts

            [{upstream, sub_opts}]
          else
            []
          end

        {:producer_consumer, state, subscribe_to: subscriptions}
      end

      @impl GenStage
      def handle_events(events, _from, state) do
        processed =
          events
          |> Enum.map(fn event -> process_with_timing(event, state) end)
          |> Enum.reject(&is_nil/1)

        {:noreply, processed, state}
      end

      @impl GenStage
      def handle_subscribe(:producer, _opts, from, state) do
        # Accept subscription from upstream
        {:automatic, state}
      end

      @impl GenStage
      def handle_subscribe(:consumer, _opts, from, state) do
        # Accept subscription from downstream
        {:automatic, state}
      end

      # Process a single event with timing instrumentation
      defp process_with_timing(event, state) do
        start_time = System.monotonic_time(:microsecond)
        stage = stage_name()

        case process(event, state) do
          {:ok, updated_event} ->
            # Record timing in the event
            timed_event = PipelineEvent.record_timing(updated_event, stage, start_time)

            # Sample stats recording to reduce ETS overhead at high throughput
            # At 10khz with 1% sampling, still get 100 samples/sec (statistically sufficient)
            if :rand.uniform(@timing_sample_rate) == 1 do
              duration = System.monotonic_time(:microsecond) - start_time
              Stats.record_timing(state.mission_id, stage, duration)
            end

            timed_event

          {:skip, reason} ->
            # Silent skip - event doesn't match this stage's criteria
            Logger.debug(
              "Stage #{stage} skipped event #{event.id}: #{inspect(reason)}",
              mission_id: state.mission_id,
              partition: state.partition
            )

            nil

          {:error, reason} ->
            Logger.error(
              "Stage #{stage} failed for event #{event.id}: #{inspect(reason)}",
              mission_id: state.mission_id,
              partition: state.partition
            )

            # Track error per-stage (also increments aggregate :stage_errors)
            Stats.increment_stage_error(state.mission_id, stage)
            nil
        end
      end

      # Default init_state returns empty map
      # Stages can override to add custom state
      def init_state(_opts), do: %{}

      # Allow stages to override max/min demand and init_state
      defoverridable start_link: 1, init: 1, init_state: 1
    end
  end
end
