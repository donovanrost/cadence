defmodule Cadence.Catalog.MissionModel.RuntimePlan do
  @moduledoc "Immutable target-specific executable Mission Model plan."

  alias Cadence.Catalog.MissionModel.{Canonical, Diagnostic, Revision}

  @targets [:telemetry, :algorithm, :monitoring, :command]

  @type target :: :telemetry | :algorithm | :monitoring | :command
  @type status :: :ready | :blocked

  @type t :: %__MODULE__{
          plan_id: binary(),
          target: target(),
          target_contract_version: binary(),
          mission_model_revision_id: binary(),
          mission_model_content_sha256: binary(),
          layer_ids: [binary()],
          compiler_version: binary(),
          status: status(),
          plan: map(),
          diagnostics: [Diagnostic.t()],
          content_sha256: binary()
        }

  @enforce_keys [
    :plan_id,
    :target,
    :target_contract_version,
    :mission_model_revision_id,
    :mission_model_content_sha256,
    :layer_ids,
    :compiler_version,
    :status,
    :content_sha256
  ]
  defstruct @enforce_keys ++ [plan: %{}, diagnostics: []]

  @spec new(Revision.t(), target(), binary(), map(), [Diagnostic.t()]) :: t()
  def new(%Revision{} = revision, target, contract_version, plan, diagnostics)
      when target in @targets and is_binary(contract_version) and is_map(plan) do
    basis = %{
      target: target,
      target_contract_version: contract_version,
      mission_model_revision_id: revision.revision_id,
      mission_model_content_sha256: revision.content_sha256,
      layer_ids: revision.layer_ids,
      compiler_version: revision.compiler_version,
      plan: plan
    }

    content_sha256 = Canonical.sha256(basis)

    %__MODULE__{
      plan_id: Canonical.content_id("mission_model_plan", basis),
      target: target,
      target_contract_version: contract_version,
      mission_model_revision_id: revision.revision_id,
      mission_model_content_sha256: revision.content_sha256,
      layer_ids: revision.layer_ids,
      compiler_version: revision.compiler_version,
      status: if(Enum.any?(diagnostics, &Diagnostic.blocking?/1), do: :blocked, else: :ready),
      plan: plan,
      diagnostics: diagnostics,
      content_sha256: content_sha256
    }
  end

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      plan_id: value(attrs, :plan_id),
      target: attrs |> value(:target) |> normalize_atom(),
      target_contract_version: value(attrs, :target_contract_version),
      mission_model_revision_id: value(attrs, :mission_model_revision_id),
      mission_model_content_sha256: value(attrs, :mission_model_content_sha256),
      layer_ids: value(attrs, :layer_ids, []),
      compiler_version: value(attrs, :compiler_version),
      status: attrs |> value(:status) |> normalize_atom(),
      plan: value(attrs, :plan, %{}),
      diagnostics: value(attrs, :diagnostics, []) |> Enum.map(&Diagnostic.new/1),
      content_sha256: value(attrs, :content_sha256)
    }
  end

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
