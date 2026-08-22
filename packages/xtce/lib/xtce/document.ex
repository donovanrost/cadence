defmodule XTCE.Document do
  @moduledoc """
  A parsed XTCE document and its identified specification version.

  The root is an `XTCE.Element` tree that retains the source-oriented XML
  structure. Consumers can translate that tree into their own domain model
  without adopting a particular ground system's semantic representation.
  """

  alias XTCE.Element

  @enforce_keys [:version, :namespace, :root]
  defstruct [:version, :namespace, :root]

  @type t :: %__MODULE__{
          version: binary(),
          namespace: binary(),
          root: Element.t()
        }

  @doc false
  @spec new(binary(), binary(), Element.t()) :: t()
  def new(version, namespace, %Element{} = root) do
    %__MODULE__{version: version, namespace: namespace, root: root}
  end
end
