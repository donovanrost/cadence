defmodule Cadence.Dashboards.ResolutionContext do
  @moduledoc """
  Explicit dependencies and policies for one dashboard resolution runtime.

  The context is assembled at an application boundary and passed unchanged to
  dashboard hydration, planning, and source execution. This keeps the engine
  independent of process-wide configuration changes while a resolve is in
  flight.
  """

  alias Cadence.Dashboards.{RuntimeCache, RuntimeComposition}

  @enforce_keys [
    :persisted?,
    :validate_dashboard_contract?,
    :persist_limit_selected_clock_audit_events?,
    :runtime_cache,
    :runtime_invalidation?,
    :plan_cache?,
    :source_result_cache?,
    :frame_cache?,
    :source_execution_opts
  ]
  defstruct persisted?: false,
            validate_dashboard_contract?: false,
            persist_limit_selected_clock_audit_events?: false,
            runtime_cache: false,
            runtime_invalidation?: true,
            plan_cache?: false,
            source_result_cache?: false,
            frame_cache?: false,
            source_execution_opts: []

  @owned_option_keys [
    :persisted?,
    :validate_dashboard_contract?,
    :persist_limit_selected_clock_audit_events?,
    :runtime_cache,
    :runtime_invalidation?,
    :plan_cache?,
    :source_result_cache?,
    :frame_cache?
  ]

  @type t :: %__MODULE__{
          persisted?: boolean(),
          validate_dashboard_contract?: boolean(),
          persist_limit_selected_clock_audit_events?: boolean(),
          runtime_cache: false | RuntimeCache.t(),
          runtime_invalidation?: boolean(),
          plan_cache?: boolean(),
          source_result_cache?: boolean(),
          frame_cache?: boolean(),
          source_execution_opts: keyword()
        }

  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    source_execution_opts = Keyword.get(opts, :source_execution_opts, [])
    validate_source_execution_opts!(source_execution_opts)

    %__MODULE__{
      persisted?: boolean_opt!(opts, :persisted?, false),
      validate_dashboard_contract?: boolean_opt!(opts, :validate_dashboard_contract?, false),
      persist_limit_selected_clock_audit_events?:
        boolean_opt!(opts, :persist_limit_selected_clock_audit_events?, false),
      runtime_cache: Keyword.get(opts, :runtime_cache, false),
      runtime_invalidation?: boolean_opt!(opts, :runtime_invalidation?, true),
      plan_cache?: boolean_opt!(opts, :plan_cache?, false),
      source_result_cache?: boolean_opt!(opts, :source_result_cache?, false),
      frame_cache?: boolean_opt!(opts, :frame_cache?, false),
      source_execution_opts: source_execution_opts
    }
  end

  @doc """
  Builds one resolution context from a captured runtime composition.

  This is the preferred constructor for production runtime roots and focused
  tests. `new!/1` remains a pure compatibility constructor for callers that
  already own every individual option.
  """
  @spec from_composition!(RuntimeComposition.t(), keyword()) :: t()
  def from_composition!(%RuntimeComposition{} = composition, opts \\ [])
      when is_list(opts) do
    source_execution_opts =
      composition
      |> RuntimeComposition.source_execution_opts(Keyword.get(opts, :source_execution_opts, []))

    new!(
      persisted?: Keyword.get(opts, :persisted?, composition.data_sources_persisted?),
      validate_dashboard_contract?: Keyword.get(opts, :validate_dashboard_contract?, false),
      persist_limit_selected_clock_audit_events?:
        Keyword.get(opts, :persist_limit_selected_clock_audit_events?, false),
      runtime_cache: composition.runtime_cache,
      runtime_invalidation?: composition.runtime_invalidation?,
      plan_cache?: composition.plan_cache?,
      source_result_cache?: composition.source_result_cache?,
      frame_cache?: composition.frame_cache?,
      source_execution_opts: source_execution_opts
    )
  end

  @spec to_engine_opts(t()) :: keyword()
  def to_engine_opts(%__MODULE__{} = context) do
    context.source_execution_opts
    |> Keyword.put(:persisted?, context.persisted?)
    |> Keyword.put(:validate_dashboard_contract?, context.validate_dashboard_contract?)
    |> Keyword.put(
      :persist_limit_selected_clock_audit_events?,
      context.persist_limit_selected_clock_audit_events?
    )
    |> Keyword.put(:runtime_cache, context.runtime_cache)
    |> Keyword.put(:plan_cache?, context.plan_cache?)
    |> Keyword.put(:source_result_cache?, context.source_result_cache?)
    |> Keyword.put(:frame_cache?, context.frame_cache?)
  end

  defp validate_source_execution_opts!(opts) when is_list(opts) do
    case Enum.filter(@owned_option_keys, &Keyword.has_key?(opts, &1)) do
      [] ->
        :ok

      reserved_keys ->
        raise ArgumentError,
              "source execution options cannot override resolution context keys: #{inspect(reserved_keys)}"
    end
  end

  defp validate_source_execution_opts!(opts) do
    raise ArgumentError, "source_execution_opts must be a keyword list, got: #{inspect(opts)}"
  end

  defp boolean_opt!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_boolean(value) -> value
      value -> raise ArgumentError, "#{key} must be a boolean, got: #{inspect(value)}"
    end
  end
end
