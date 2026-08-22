defmodule Cadence.Dashboards.Frame do
  @moduledoc """
  Normalized dashboard data frame.

  Sources differ; widgets consume Frames.
  """

  alias Cadence.Dashboards.Field
  alias Cadence.DataSources.AdapterRegistry
  alias Cadence.Platform.ContractNormalization

  @type source :: atom()
  @type shape :: :scalar | :wide | :long | :events | :intervals | :matrix

  @type t :: %__MODULE__{
          frame_id: binary() | nil,
          source: source(),
          shape: shape(),
          time_axis: :generation_time | :receipt_time | :occurred_at | nil,
          scope: map(),
          fields: [Field.t()],
          overlays: map(),
          meta: map()
        }

  defstruct [
    :frame_id,
    :source,
    :shape,
    :time_axis,
    scope: %{},
    fields: [],
    overlays: %{},
    meta: %{}
  ]

  @shapes [:scalar, :wide, :long, :events, :intervals, :matrix]
  @time_axes [:generation_time, :receipt_time, :occurred_at]

  @spec sources(keyword()) :: [source()]
  def sources(opts \\ []), do: opts |> adapter_policy() |> AdapterRegistry.logical_sources()

  @spec shapes() :: [shape()]
  def shapes, do: @shapes

  @spec time_axes() :: [:generation_time | :receipt_time | :occurred_at]
  def time_axes, do: @time_axes

  @spec new(map() | t(), keyword()) :: t()
  def new(attrs, opts \\ []), do: normalize(attrs, opts)

  @spec normalize(map() | t(), keyword()) :: t() | nil
  def normalize(frame, opts \\ [])

  def normalize(%__MODULE__{} = frame, opts) do
    %__MODULE__{
      frame
      | source: ContractNormalization.known_atom(frame.source, sources(opts)),
        shape: ContractNormalization.known_atom(frame.shape, @shapes),
        time_axis: ContractNormalization.known_atom(frame.time_axis, @time_axes),
        scope: ContractNormalization.map_or_default(frame.scope),
        fields: normalize_fields(frame.fields),
        overlays: ContractNormalization.map_or_default(frame.overlays),
        meta: ContractNormalization.map_or_default(frame.meta)
    }
  end

  def normalize(frame, opts) when is_map(frame) do
    %__MODULE__{
      frame_id: ContractNormalization.attr(frame, :frame_id),
      source:
        frame
        |> ContractNormalization.attr(:source)
        |> ContractNormalization.known_atom(sources(opts)),
      shape:
        frame
        |> ContractNormalization.attr(:shape)
        |> ContractNormalization.known_atom(@shapes),
      time_axis:
        frame
        |> ContractNormalization.attr(:time_axis)
        |> ContractNormalization.known_atom(@time_axes),
      scope:
        frame
        |> ContractNormalization.attr(:scope, %{})
        |> ContractNormalization.map_or_default(),
      fields:
        frame
        |> ContractNormalization.attr(:fields, [])
        |> normalize_fields(),
      overlays:
        frame
        |> ContractNormalization.attr(:overlays, %{})
        |> ContractNormalization.map_or_default(),
      meta:
        frame
        |> ContractNormalization.attr(:meta, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  def normalize(_other, _opts), do: nil

  defp adapter_policy(opts) do
    Keyword.get_lazy(opts, :data_source_adapter_policy, &AdapterRegistry.default_policy/0)
  end

  defp normalize_fields(fields) when is_list(fields),
    do: Enum.map(fields, &(Field.normalize(&1) || &1))

  defp normalize_fields(fields), do: fields
end
