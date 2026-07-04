defmodule Cadence.Dashboards.ResolveWarning do
  @moduledoc """
  Structured dashboard engine warning.
  """

  alias Cadence.Dashboards.{ContractNormalization, DataLink, EvidenceRef}

  @severities [:info, :warning, :error]
  @scopes [:dashboard, :placement, :frame, :field]

  @type severity :: :info | :warning | :error
  @type scope :: :dashboard | :placement | :frame | :field

  @type t :: %__MODULE__{
          code: atom(),
          severity: severity(),
          scope: scope(),
          placement_id: binary() | nil,
          frame_id: binary() | nil,
          field_name: binary() | nil,
          message: binary() | nil,
          details: map(),
          evidence: [EvidenceRef.t()],
          links: [DataLink.t()]
        }

  defstruct [
    :code,
    :placement_id,
    :frame_id,
    :field_name,
    :message,
    severity: :warning,
    scope: :dashboard,
    details: %{},
    evidence: [],
    links: []
  ]

  @spec severities() :: [severity()]
  def severities, do: @severities

  @spec severity?(term()) :: boolean()
  def severity?(severity), do: severity in @severities

  @spec scopes() :: [scope()]
  def scopes, do: @scopes

  @spec scope?(term()) :: boolean()
  def scope?(scope), do: scope in @scopes

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = warning) do
    %__MODULE__{
      warning
      | code: ContractNormalization.existing_atom(warning.code),
        severity: ContractNormalization.known_atom(warning.severity, @severities),
        scope: ContractNormalization.known_atom(warning.scope, @scopes),
        details: ContractNormalization.map_or_default(warning.details),
        evidence: normalize_evidence_refs(warning.evidence),
        links: normalize_data_links(warning.links)
    }
  end

  def normalize(warning) when is_map(warning) do
    %__MODULE__{
      code: warning |> ContractNormalization.attr(:code) |> ContractNormalization.existing_atom(),
      severity:
        warning
        |> ContractNormalization.attr(:severity, :warning)
        |> ContractNormalization.known_atom(@severities),
      scope:
        warning
        |> ContractNormalization.attr(:scope, :dashboard)
        |> ContractNormalization.known_atom(@scopes),
      placement_id: ContractNormalization.attr(warning, :placement_id),
      frame_id: ContractNormalization.attr(warning, :frame_id),
      field_name: ContractNormalization.attr(warning, :field_name),
      message: ContractNormalization.attr(warning, :message),
      details:
        warning
        |> ContractNormalization.attr(:details, %{})
        |> ContractNormalization.map_or_default(),
      evidence: warning |> ContractNormalization.attr(:evidence, []) |> normalize_evidence_refs(),
      links: warning |> ContractNormalization.attr(:links, []) |> normalize_data_links()
    }
  end

  defp normalize_evidence_refs(refs) when is_list(refs) do
    Enum.map(refs, fn ref -> EvidenceRef.normalize(ref) || ref end)
  end

  defp normalize_evidence_refs(nil), do: []
  defp normalize_evidence_refs(refs), do: refs

  defp normalize_data_links(links) when is_list(links) do
    Enum.map(links, fn link -> DataLink.normalize(link) || link end)
  end

  defp normalize_data_links(nil), do: []
  defp normalize_data_links(links), do: links
end
