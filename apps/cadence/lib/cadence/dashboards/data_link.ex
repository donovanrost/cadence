defmodule Cadence.Dashboards.DataLink do
  @moduledoc """
  Context-preserving navigation link from dashboard data to Cadence evidence.

  Data links point at records the dashboard inspector can resolve directly.
  Future command, source-management, or cross-application navigation actions
  should use a separate action/navigation contract instead of overloading this
  evidence-resolution target set.
  """

  alias Cadence.Dashboards.ContractNormalization

  @resolvable_targets [
    :telemetry_point,
    :telemetry_sample,
    :raw_evidence,
    :limit_event,
    :limit_definition,
    :limit_definition_interval,
    :limit_definition_lifecycle_event,
    :mission_event,
    :operational_event,
    :binding_set_interval,
    :application_binding_interval,
    :catalog_revision_interval,
    :source_binding_interval,
    :transport_execution_interval,
    :transport_connection_state_interval,
    :ground_station_connection_state_interval,
    :ground_station_antenna_pointing_state_interval,
    :link_rf_lock_state_interval,
    :link_frame_sync_state_interval,
    :source_health_event,
    :source_watermark_event,
    :source_binding_event,
    :comparison_finding,
    :telemetry_revision_decision_event,
    :telemetry_backfill_lifecycle_event,
    :contact,
    :transport,
    :link,
    :source_endpoint,
    :ground_station
  ]

  @presentations [:side_panel, :navigate, :new_tab, :explore]
  @sources [:widget, :field, :warning, :annotation, :frame]
  @relationship_kinds [
    :evidence,
    :source_event,
    :retry_event,
    :correction_request,
    :correction_transition,
    :late_data_policy_event,
    :stage_transition_event,
    :follow_up_event
  ]

  @type resolvable_target ::
          :telemetry_point
          | :telemetry_sample
          | :raw_evidence
          | :limit_event
          | :limit_definition
          | :limit_definition_interval
          | :limit_definition_lifecycle_event
          | :mission_event
          | :operational_event
          | :binding_set_interval
          | :application_binding_interval
          | :catalog_revision_interval
          | :source_binding_interval
          | :transport_execution_interval
          | :transport_connection_state_interval
          | :ground_station_connection_state_interval
          | :ground_station_antenna_pointing_state_interval
          | :link_rf_lock_state_interval
          | :link_frame_sync_state_interval
          | :source_health_event
          | :source_watermark_event
          | :source_binding_event
          | :comparison_finding
          | :telemetry_revision_decision_event
          | :telemetry_backfill_lifecycle_event
          | :contact
          | :transport
          | :link
          | :source_endpoint
          | :ground_station

  @type target :: resolvable_target()

  @type t :: %__MODULE__{
          link_id: binary() | nil,
          label: binary(),
          target: target(),
          target_id: binary() | nil,
          route: binary() | nil,
          relationship_kind: relationship_kind() | nil,
          context: map(),
          presentation: presentation(),
          source: source()
        }

  @type presentation :: :side_panel | :navigate | :new_tab | :explore
  @type source :: :widget | :field | :warning | :annotation | :frame
  @type relationship_kind ::
          :evidence
          | :source_event
          | :retry_event
          | :correction_request
          | :correction_transition
          | :late_data_policy_event
          | :stage_transition_event
          | :follow_up_event

  defstruct [
    :link_id,
    :label,
    :target,
    :target_id,
    :route,
    :relationship_kind,
    context: %{},
    presentation: :side_panel,
    source: :field
  ]

  @spec resolvable_targets() :: [resolvable_target()]
  def resolvable_targets, do: @resolvable_targets

  @spec resolvable_target?(term()) :: boolean()
  def resolvable_target?(target), do: target in @resolvable_targets

  @spec presentations() :: [presentation()]
  def presentations, do: @presentations

  @spec presentation?(term()) :: boolean()
  def presentation?(presentation), do: presentation in @presentations

  @spec sources() :: [source()]
  def sources, do: @sources

  @spec source?(term()) :: boolean()
  def source?(source), do: source in @sources

  @spec relationship_kinds() :: [relationship_kind()]
  def relationship_kinds, do: @relationship_kinds

  @spec relationship_kind?(term()) :: boolean()
  def relationship_kind?(relationship_kind), do: relationship_kind in @relationship_kinds

  @spec parse_resolvable_target(term()) :: resolvable_target() | nil
  def parse_resolvable_target(target) when is_atom(target) do
    if resolvable_target?(target), do: target
  end

  def parse_resolvable_target(target) when is_binary(target) do
    case ContractNormalization.known_atom(target, @resolvable_targets) do
      target when target in @resolvable_targets -> target
      _unsupported -> nil
    end
  end

  def parse_resolvable_target(_target), do: nil

  @spec normalize(term()) :: t() | nil
  def normalize(%__MODULE__{} = link), do: link

  def normalize(link) when is_map(link) do
    %__MODULE__{
      link_id: ContractNormalization.attr(link, :link_id),
      label: ContractNormalization.attr(link, :label),
      target:
        link
        |> ContractNormalization.attr(:target)
        |> ContractNormalization.known_atom(@resolvable_targets),
      target_id: ContractNormalization.attr(link, :target_id),
      route: ContractNormalization.attr(link, :route),
      relationship_kind:
        link
        |> ContractNormalization.attr(:relationship_kind)
        |> ContractNormalization.known_atom(@relationship_kinds)
        |> normalize_relationship_kind(),
      context:
        link |> ContractNormalization.attr(:context) |> ContractNormalization.map_or_default(),
      presentation:
        link
        |> ContractNormalization.attr(:presentation, :side_panel)
        |> ContractNormalization.known_atom(@presentations),
      source:
        link
        |> ContractNormalization.attr(:source, :field)
        |> ContractNormalization.known_atom(@sources)
    }
  end

  def normalize(_link), do: nil

  defp normalize_relationship_kind(kind) when kind in @relationship_kinds, do: kind
  defp normalize_relationship_kind(_kind), do: nil

  @spec normalize_many(term()) :: [t()]
  def normalize_many(links) when is_list(links) do
    links
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_many(_links), do: []
end
