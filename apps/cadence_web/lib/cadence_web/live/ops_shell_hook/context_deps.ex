defmodule CadenceWeb.OpsShellHook.ContextDeps do
  @moduledoc false

  alias Cadence.Reads.{Alarms, Commands}
  alias Cadence.Reads.MissionHealth, as: MissionHealthReads

  @default_refresh_interval_ms 15_000

  @enforce_keys [
    :mission_health_summary,
    :alarm_summary,
    :command_summary,
    :observed_at,
    :refresh_interval_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          mission_health_summary: function(),
          alarm_summary: function(),
          command_summary: function(),
          observed_at: function(),
          refresh_interval_ms: pos_integer()
        }

  @spec from_config() :: t()
  def from_config do
    refresh_interval_ms =
      Application.get_env(
        :cadence_web,
        :ops_context_refresh_ms,
        @default_refresh_interval_ms
      )

    new(refresh_interval_ms: refresh_interval_ms)
  end

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      mission_health_summary:
        collaborator(
          opts,
          :mission_health_summary,
          3,
          &MissionHealthReads.summary/3
        ),
      alarm_summary: collaborator(opts, :alarm_summary, 3, &default_alarm_summary/3),
      command_summary: collaborator(opts, :command_summary, 3, &default_command_summary/3),
      observed_at: collaborator(opts, :observed_at, 0, &DateTime.utc_now/0),
      refresh_interval_ms: refresh_interval_ms(opts)
    }
  end

  defp collaborator(opts, key, arity, default) do
    case Keyword.get(opts, key) do
      callback when is_function(callback, arity) -> callback
      _missing_or_invalid -> default
    end
  end

  defp refresh_interval_ms(opts) do
    case Keyword.get(opts, :refresh_interval_ms, @default_refresh_interval_ms) do
      refresh_ms when is_integer(refresh_ms) and refresh_ms > 0 -> refresh_ms
      _invalid -> @default_refresh_interval_ms
    end
  end

  defp default_alarm_summary(organization_id, mission_id, _opts) do
    Alarms.summary(organization_id, mission_id)
  end

  defp default_command_summary(organization_id, mission_id, _opts) do
    Commands.summary(organization_id, mission_id)
  end
end
