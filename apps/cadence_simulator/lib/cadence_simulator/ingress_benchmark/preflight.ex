defmodule CadenceSimulator.IngressBenchmark.Preflight do
  @moduledoc """
  Successful laptop safety evaluation required by runnable harness components.
  """

  alias CadenceSimulator.IngressBenchmark.{LocalSafety, Manifest}

  @enforce_keys [:manifest, :safety]
  defstruct [:manifest, :safety]

  @type t :: %__MODULE__{
          manifest: Manifest.t(),
          safety: LocalSafety.report()
        }

  @spec evaluate(Manifest.t(), keyword()) :: {:ok, t()} | {:error, [binary()]}
  def evaluate(%Manifest{} = manifest, opts \\ []) when is_list(opts) do
    case LocalSafety.validate(manifest.data, opts) do
      {:ok, safety} -> {:ok, %__MODULE__{manifest: manifest, safety: safety}}
      {:error, errors} -> {:error, errors}
    end
  end

  @spec result(t()) :: map()
  def result(%__MODULE__{} = preflight) do
    %{
      status: "passed",
      qualification: "local_safety_only",
      manifest: %{
        path: preflight.manifest.path,
        sha256: preflight.manifest.sha256
      },
      safety: preflight.safety
    }
  end
end
