defmodule Cadence.Dashboards.DashboardResolveRequest do
  @moduledoc """
  Request passed to the dashboard engine.
  """

  alias Cadence.Dashboards.{DataContext, Document, LimitContext, ScopeContext, TimeContext}

  @resolve_modes [:initial, :context_change, :live_tick, :stream_append]
  @document_modes [:published, :draft, :draft_preview]

  @type resolve_mode :: :initial | :context_change | :live_tick | :stream_append
  @type document_mode :: :published | :draft | :draft_preview

  @type t :: %__MODULE__{
          organization_id: binary(),
          mission_id: binary(),
          dashboard_id: binary(),
          document: Document.t(),
          document_mode: document_mode(),
          resolve_mode: resolve_mode(),
          time_context: TimeContext.t() | map(),
          scope_context: ScopeContext.t() | map(),
          data_context: DataContext.t() | map(),
          limit_context: LimitContext.t() | map(),
          interaction_context: map()
        }

  defstruct [
    :organization_id,
    :mission_id,
    :dashboard_id,
    :document,
    document_mode: :draft,
    resolve_mode: :initial,
    time_context: %TimeContext{},
    scope_context: %ScopeContext{},
    data_context: %DataContext{},
    limit_context: %LimitContext{},
    interaction_context: %{}
  ]

  @spec resolve_modes() :: [resolve_mode()]
  def resolve_modes, do: @resolve_modes

  @spec resolve_mode?(term()) :: boolean()
  def resolve_mode?(resolve_mode), do: resolve_mode in @resolve_modes

  @spec document_modes() :: [document_mode()]
  def document_modes, do: @document_modes

  @spec document_mode?(term()) :: boolean()
  def document_mode?(document_mode), do: document_mode in @document_modes

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = request) do
    %__MODULE__{
      request
      | document_mode: known_atom(request.document_mode, @document_modes),
        resolve_mode: known_atom(request.resolve_mode, @resolve_modes),
        time_context: normalize_context(request.time_context, TimeContext),
        scope_context: normalize_context(request.scope_context, ScopeContext),
        data_context: normalize_context(request.data_context, DataContext),
        limit_context: normalize_context(request.limit_context, LimitContext),
        interaction_context: ensure_map(request.interaction_context)
    }
  end

  def normalize(attrs) when is_map(attrs) do
    %__MODULE__{
      organization_id: attr(attrs, :organization_id),
      mission_id: attr(attrs, :mission_id),
      dashboard_id: attr(attrs, :dashboard_id),
      document: attr(attrs, :document),
      document_mode: attr(attrs, :document_mode, :draft) |> known_atom(@document_modes),
      resolve_mode: attr(attrs, :resolve_mode, :initial) |> known_atom(@resolve_modes),
      time_context: attr(attrs, :time_context, %{}) |> normalize_context(TimeContext),
      scope_context: attr(attrs, :scope_context, %{}) |> normalize_context(ScopeContext),
      data_context: attr(attrs, :data_context, %{}) |> normalize_context(DataContext),
      limit_context: attr(attrs, :limit_context, %{}) |> normalize_context(LimitContext),
      interaction_context: attr(attrs, :interaction_context, %{}) |> ensure_map()
    }
  end

  defp normalize_context(nil, module), do: module.from_map(nil)

  defp normalize_context(value, module) when is_map(value), do: module.from_map(value)

  defp normalize_context(value, _module), do: value

  defp attr(attrs, key, default \\ nil) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp known_atom(value, known_values) when is_atom(value) do
    if value in known_values, do: value, else: value
  end

  defp known_atom(value, known_values) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(known_values, &(Atom.to_string(&1) == normalized)) || value
  end

  defp known_atom(value, _known_values), do: value

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}
end
