defmodule Cadence.SemanticRuntime.TestProbe do
  @moduledoc false
  # Loaded only by Cadence.SemanticRuntime.TermsTest. Its field atom exists in the VM only once
  # this module loads, which reproduces a semantic runtime struct not yet loaded in dev.
  defstruct [:semantic_runtime_probe_field_q7x]
end
