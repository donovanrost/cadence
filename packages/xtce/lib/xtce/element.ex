defmodule XTCE.Element do
  @moduledoc """
  A source-oriented XML element from an XTCE document.

  Elements retain their local name, namespace, attributes, ordered children,
  direct text content, and source line. The representation is intentionally
  small and does not impose a ground-system or runtime-specific semantic model.
  """

  @type t :: %__MODULE__{
          name: binary(),
          namespace: binary() | nil,
          attributes: map(),
          children: [t()],
          text: binary(),
          line: pos_integer() | nil
        }

  defstruct [:name, :namespace, :line, attributes: %{}, children: [], text: ""]

  @doc "Returns an attribute value or the supplied default."
  @spec attr(t(), binary(), term()) :: term()
  def attr(%__MODULE__{attributes: attributes}, name, default \\ nil),
    do: Map.get(attributes, name, default)

  @doc "Returns the first direct child with the given local name."
  @spec child(t(), binary()) :: t() | nil
  def child(%__MODULE__{children: children}, name), do: Enum.find(children, &(&1.name == name))

  @doc "Returns all direct children with the given local name."
  @spec children(t(), binary()) :: [t()]
  def children(%__MODULE__{children: children}, name),
    do: Enum.filter(children, &(&1.name == name))

  @doc "Returns descendants matching a local name or predicate."
  @spec descendants(t(), binary() | (t() -> boolean())) :: [t()]
  def descendants(%__MODULE__{} = element, name) when is_binary(name),
    do: descendants(element, &(&1.name == name))

  def descendants(%__MODULE__{children: children}, predicate) when is_function(predicate, 1) do
    Enum.flat_map(children, fn child ->
      matches = if predicate.(child), do: [child], else: []
      matches ++ descendants(child, predicate)
    end)
  end

  @doc "Returns trimmed direct text content."
  @spec text(t()) :: binary()
  def text(%__MODULE__{text: text}), do: String.trim(text)

  @doc "Converts the complete element tree into string-keyed maps."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = element) do
    %{
      "name" => element.name,
      "namespace" => element.namespace,
      "attributes" => element.attributes,
      "children" => Enum.map(element.children, &to_map/1),
      "text" => element.text,
      "line" => element.line
    }
  end
end
