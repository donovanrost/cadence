defmodule Cadence.ApplicationDispatch.CapabilityConfig do
  @moduledoc """
  First-class governed capability configuration document.
  """

  alias Cadence.Telemetry.PacketDefinition

  @type config_type :: :none | :governed_packet_definition | :inline

  @type t :: %__MODULE__{
          config_type: config_type(),
          document: map()
        }

  defstruct [:config_type, document: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      config_type:
        normalize_config_type(Map.get(attrs, :config_type, Map.get(attrs, "config_type", :none))),
      document: Map.get(attrs, :document, Map.get(attrs, "document", %{}))
    }
  end

  @spec none() :: t()
  def none, do: %__MODULE__{config_type: :none, document: %{}}

  @spec reference_packet_definition(PacketDefinition.t()) :: t()
  def reference_packet_definition(%PacketDefinition{} = packet_definition) do
    %__MODULE__{
      config_type: :governed_packet_definition,
      document: %{
        "mission_id" => packet_definition.mission_id,
        "packet_definition_id" => packet_definition.packet_definition_id,
        "version" => packet_definition.version
      }
    }
  end

  @spec inline(map()) :: t()
  def inline(document) when is_map(document) do
    %__MODULE__{
      config_type: :inline,
      document: document
    }
  end

  @spec packet_definition_ref(t()) :: {binary() | nil, binary() | nil, pos_integer() | nil} | nil
  def packet_definition_ref(%__MODULE__{
        config_type: :governed_packet_definition,
        document: document
      })
      when is_map(document) do
    {
      Map.get(document, "mission_id", Map.get(document, :mission_id)),
      Map.get(document, "packet_definition_id", Map.get(document, :packet_definition_id)),
      Map.get(document, "version", Map.get(document, :version))
    }
  end

  def packet_definition_ref(%__MODULE__{}), do: nil

  @spec inline_document(t()) :: map() | nil
  def inline_document(%__MODULE__{config_type: :inline, document: document})
      when is_map(document),
      do: document

  def inline_document(%__MODULE__{}), do: nil

  defp normalize_config_type(nil), do: :none
  defp normalize_config_type(:none), do: :none
  defp normalize_config_type("none"), do: :none
  defp normalize_config_type(:governed_packet_definition), do: :governed_packet_definition
  defp normalize_config_type("governed_packet_definition"), do: :governed_packet_definition
  defp normalize_config_type(:inline), do: :inline
  defp normalize_config_type("inline"), do: :inline

  defp normalize_config_type(config_type) do
    raise ArgumentError, "unsupported capability config type: #{inspect(config_type)}"
  end
end
