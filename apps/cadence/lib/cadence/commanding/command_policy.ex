defmodule Cadence.Commanding.CommandPolicy do
  @moduledoc """
  The two-person rule for command groups (DECISIONS #7, #31), the single source
  for preflight, submit, review and the console's policy text (O4).

  A second operator's GO is required when any command in the stack needs one
  on its own (critical, hazardous, critical/hazardous significance, or a
  confirmation/approval policy hint, the same predicate single requests use),
  or when the group reaches `fleet_reach_threshold/0` targets or more.
  Reasons carry stable keys plus facts; the UI words them.
  """

  alias Cadence.Commanding.RequestValidation

  @policy_version 1
  @default_fleet_reach_threshold 10

  @type command :: %{
          required(:command_id) => binary(),
          required(:name) => binary() | nil,
          optional(:significance) => atom() | nil,
          optional(:critical) => boolean(),
          optional(:hazardous) => boolean(),
          optional(:release_policy_hint) => binary() | nil
        }

  @type reason ::
          %{
            key: :hazardous_command | :critical_command | :policy_hint,
            command_id: binary(),
            name: binary() | nil
          }
          | %{key: :fleet_reach, targets: non_neg_integer(), threshold: pos_integer()}

  @spec evaluate([command()], non_neg_integer(), keyword()) :: %{
          second_go_required: boolean(),
          reasons: [reason()],
          policy_version: pos_integer()
        }
  def evaluate(commands, target_count, opts \\ []) when is_list(commands) do
    threshold = Keyword.get_lazy(opts, :fleet_reach_threshold, &fleet_reach_threshold/0)

    reasons =
      commands
      |> Enum.flat_map(&command_reason/1)
      |> Enum.uniq_by(& &1.command_id)
      |> Kernel.++(fleet_reason(target_count, threshold))

    %{second_go_required: reasons != [], reasons: reasons, policy_version: @policy_version}
  end

  @doc "Configured fleet-reach threshold (`config :cadence, :command_group_fleet_reach_threshold`)."
  @spec fleet_reach_threshold() :: pos_integer()
  def fleet_reach_threshold,
    do:
      Application.get_env(
        :cadence,
        :command_group_fleet_reach_threshold,
        @default_fleet_reach_threshold
      )

  @doc "The policies as data for the console's policy text (O4)."
  @spec policies() :: [map()]
  def policies do
    [
      %{key: :command_classification, parameters: %{classifications: ~w(hazardous critical)}},
      %{key: :policy_hint, parameters: %{hints: ~w(confirmation_required approval_required)}},
      %{key: :fleet_reach, parameters: %{threshold: fleet_reach_threshold()}},
      %{key: :no_self_approval, parameters: %{}}
    ]
  end

  defp command_reason(command) do
    significance = Map.get(command, :significance)
    critical = Map.get(command, :critical, false)
    hazardous = Map.get(command, :hazardous, false)
    hint = Map.get(command, :release_policy_hint)

    cond do
      not RequestValidation.approval_required?(significance, critical, hazardous, hint) -> []
      hazardous or significance == :hazardous -> [reason(:hazardous_command, command)]
      critical or significance == :critical -> [reason(:critical_command, command)]
      true -> [reason(:policy_hint, command)]
    end
  end

  defp reason(key, command), do: %{key: key, command_id: command.command_id, name: command.name}

  defp fleet_reason(count, threshold) when count >= threshold,
    do: [%{key: :fleet_reach, targets: count, threshold: threshold}]

  defp fleet_reason(_count, _threshold), do: []
end
