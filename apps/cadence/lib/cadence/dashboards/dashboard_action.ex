defmodule Cadence.Dashboards.DashboardAction do
  @moduledoc """
  Typed dashboard action/navigation contract.

  Dashboard actions are commands to move the operator into another workflow or
  invoke a non-evidence operation. They are intentionally separate from
  `Cadence.Dashboards.DataLink`, which is reserved for records the dashboard
  evidence inspector can resolve directly.
  """

  alias Cadence.Dashboards.ContractNormalization

  @targets [
    :telemetry_explore,
    :source_inventory,
    :source_health,
    :routing_rule,
    :dashboard_editor,
    :command
  ]

  @presentations [:button, :menu_item, :inline_link]
  @kinds [:navigate, :new_tab, :invoke]
  @sources [:data_link_panel, :evidence_panel, :warning, :source_health, :widget, :frame, :field]

  @type target ::
          :telemetry_explore
          | :source_inventory
          | :source_health
          | :routing_rule
          | :dashboard_editor
          | :command
  @type presentation :: :button | :menu_item | :inline_link
  @type kind :: :navigate | :new_tab | :invoke
  @type source ::
          :data_link_panel
          | :evidence_panel
          | :warning
          | :source_health
          | :widget
          | :frame
          | :field

  @type t :: %__MODULE__{
          action_id: binary(),
          label: binary(),
          message: binary() | nil,
          target: target(),
          kind: kind(),
          route: binary() | nil,
          query: map(),
          context: map(),
          presentation: presentation(),
          source: source()
        }

  defstruct [
    :action_id,
    :label,
    :message,
    :target,
    :kind,
    :route,
    query: %{},
    context: %{},
    presentation: :button,
    source: :widget
  ]

  @spec targets() :: [target()]
  def targets, do: @targets

  @spec target?(term()) :: boolean()
  def target?(target), do: target in @targets

  @spec presentations() :: [presentation()]
  def presentations, do: @presentations

  @spec presentation?(term()) :: boolean()
  def presentation?(presentation), do: presentation in @presentations

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @spec kind?(term()) :: boolean()
  def kind?(kind), do: kind in @kinds

  @spec sources() :: [source()]
  def sources, do: @sources

  @spec source?(term()) :: boolean()
  def source?(source), do: source in @sources

  @spec normalize(term()) :: t() | nil
  def normalize(%__MODULE__{} = action), do: action

  def normalize(action) when is_map(action) do
    %__MODULE__{
      action_id: ContractNormalization.attr(action, :action_id),
      label: ContractNormalization.attr(action, :label),
      message: ContractNormalization.attr(action, :message),
      target:
        action
        |> ContractNormalization.attr(:target)
        |> ContractNormalization.known_atom(@targets),
      kind:
        action |> ContractNormalization.attr(:kind) |> ContractNormalization.known_atom(@kinds),
      route: ContractNormalization.attr(action, :route),
      query:
        action |> ContractNormalization.attr(:query) |> ContractNormalization.map_or_default(),
      context:
        action |> ContractNormalization.attr(:context) |> ContractNormalization.map_or_default(),
      presentation:
        action
        |> ContractNormalization.attr(:presentation, :button)
        |> ContractNormalization.known_atom(@presentations),
      source:
        action
        |> ContractNormalization.attr(:source, :widget)
        |> ContractNormalization.known_atom(@sources)
    }
  end

  def normalize(_action), do: nil

  @spec normalize_many(term()) :: [t()]
  def normalize_many(actions) when is_list(actions) do
    actions
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_many(_actions), do: []
end
