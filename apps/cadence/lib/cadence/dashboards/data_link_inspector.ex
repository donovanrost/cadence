defmodule Cadence.Dashboards.DataLinkInspector do
  @moduledoc """
  Typed payload returned by data-link resolution for the dashboard inspector.

  The inspector is the contract between resolver code that knows how to load
  mission records and UI code that renders operator investigation state.
  """

  alias Cadence.Dashboards.{DashboardAction, DataLink}
  alias Cadence.Platform.ContractNormalization

  @statuses [:resolved, :context_only, :missing, :unsupported]

  @type status :: :resolved | :context_only | :missing | :unsupported

  @type row :: %{
          label: binary() | nil,
          value: binary() | nil
        }

  @type navigation :: map() | nil

  @type t :: %__MODULE__{
          status: status(),
          status_text: binary(),
          title: binary(),
          message: binary() | nil,
          target: atom(),
          target_text: binary(),
          target_id: binary() | nil,
          link_id: binary() | nil,
          link_label: binary() | nil,
          source: atom() | nil,
          source_text: binary(),
          source_context: map(),
          rows: [row()],
          context_rows: [row()],
          navigation: navigation(),
          related_links: [DataLink.t()],
          actions: [DashboardAction.t()]
        }

  defstruct [
    :status,
    :status_text,
    :title,
    :message,
    :target,
    :target_text,
    :target_id,
    :link_id,
    :link_label,
    :source,
    :source_text,
    source_context: %{},
    rows: [],
    context_rows: [],
    navigation: nil,
    related_links: [],
    actions: []
  ]

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @spec status?(term()) :: boolean()
  def status?(status), do: status in @statuses

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = inspector) do
    status = normalize_status(inspector.status)

    %__MODULE__{
      inspector
      | status: status,
        status_text: status_text(status, inspector.status_text),
        source_context: ContractNormalization.map_or_default(inspector.source_context),
        rows: normalize_rows(inspector.rows),
        context_rows: normalize_rows(inspector.context_rows),
        navigation: normalize_navigation(inspector.navigation),
        related_links: DataLink.normalize_many(inspector.related_links),
        actions: DashboardAction.normalize_many(inspector.actions)
    }
  end

  def normalize(attrs) when is_map(attrs) do
    status = attrs |> ContractNormalization.attr(:status) |> normalize_status()

    %__MODULE__{
      status: status,
      status_text: status_text(status, ContractNormalization.attr(attrs, :status_text)),
      title: text_or_nil(ContractNormalization.attr(attrs, :title)),
      message: text_or_nil(ContractNormalization.attr(attrs, :message)),
      target:
        attrs |> ContractNormalization.attr(:target) |> ContractNormalization.existing_atom(),
      target_text: text_or_nil(ContractNormalization.attr(attrs, :target_text)),
      target_id: text_or_nil(ContractNormalization.attr(attrs, :target_id)),
      link_id: text_or_nil(ContractNormalization.attr(attrs, :link_id)),
      link_label: text_or_nil(ContractNormalization.attr(attrs, :link_label)),
      source:
        attrs |> ContractNormalization.attr(:source) |> ContractNormalization.existing_atom(),
      source_text: text_or_nil(ContractNormalization.attr(attrs, :source_text)),
      source_context:
        attrs |> ContractNormalization.attr(:source_context, %{}) |> normalize_source_context(),
      rows:
        attrs
        |> ContractNormalization.attr(:rows, [])
        |> normalize_rows(),
      context_rows:
        attrs
        |> ContractNormalization.attr(:context_rows, [])
        |> normalize_rows(),
      navigation:
        attrs
        |> ContractNormalization.attr(:navigation)
        |> normalize_navigation(),
      related_links:
        attrs
        |> ContractNormalization.attr(:related_links, [])
        |> DataLink.normalize_many(),
      actions:
        attrs
        |> ContractNormalization.attr(:actions, [])
        |> DashboardAction.normalize_many()
    }
  end

  defp normalize_status(status) do
    status =
      status
      |> ContractNormalization.existing_atom()

    if status in @statuses, do: status, else: :missing
  end

  defp status_text(status, nil), do: Atom.to_string(status)
  defp status_text(_status, value), do: text_or_nil(value)

  defp normalize_rows(rows) when is_list(rows) do
    rows
    |> Enum.map(&normalize_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_rows(_rows), do: []

  defp normalize_row(%{label: label, value: value}), do: row(label, value)
  defp normalize_row(%{"label" => label, "value" => value}), do: row(label, value)
  defp normalize_row(_row), do: nil

  defp row(label, value) do
    %{label: text_or_nil(label), value: text_or_nil(value)}
  end

  defp normalize_source_context(context) when is_map(context), do: context
  defp normalize_source_context(_context), do: %{}

  defp normalize_navigation(nil), do: nil
  defp normalize_navigation(navigation) when is_map(navigation), do: navigation
  defp normalize_navigation(_navigation), do: nil

  defp text_or_nil(nil), do: nil
  defp text_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp text_or_nil(value) when is_binary(value), do: value
  defp text_or_nil(value), do: to_string(value)
end
