defmodule Cadence.Catalog.Importers.Xtce13.Element do
  @moduledoc "Small source-preserving XML element used by the XTCE importer."

  @type t :: %__MODULE__{
          name: binary(),
          namespace: binary() | nil,
          attributes: map(),
          children: [t()],
          text: binary(),
          line: pos_integer() | nil
        }

  defstruct [:name, :namespace, :line, attributes: %{}, children: [], text: ""]

  @spec attr(t(), binary(), term()) :: term()
  def attr(%__MODULE__{attributes: attributes}, name, default \\ nil),
    do: Map.get(attributes, name, default)

  @spec child(t(), binary()) :: t() | nil
  def child(%__MODULE__{children: children}, name), do: Enum.find(children, &(&1.name == name))

  @spec children(t(), binary()) :: [t()]
  def children(%__MODULE__{children: children}, name),
    do: Enum.filter(children, &(&1.name == name))

  @spec descendants(t(), binary() | (t() -> boolean())) :: [t()]
  def descendants(%__MODULE__{} = element, name) when is_binary(name),
    do: descendants(element, &(&1.name == name))

  def descendants(%__MODULE__{children: children}, predicate) when is_function(predicate, 1) do
    Enum.flat_map(children, fn child ->
      matches = if predicate.(child), do: [child], else: []
      matches ++ descendants(child, predicate)
    end)
  end

  @spec text(t()) :: binary()
  def text(%__MODULE__{text: text}), do: String.trim(text)

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
