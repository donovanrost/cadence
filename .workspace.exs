[
  ignore_paths: ["cover", "deps", "legacy", "priv", "var"],
  checks: [
    [
      id: :valid_layers,
      module: Workspace.Checks.ValidateTags,
      description: "Cadence projects use only recognized architecture layers",
      opts: [
        allowed: [
          {:layer, :foundation},
          {:layer, :domain},
          {:layer, :application}
        ]
      ]
    ],
    [
      id: :required_layer,
      module: Workspace.Checks.RequiredScopeTag,
      description: "every Cadence project declares one architecture layer",
      opts: [scope: :layer]
    ],
    [
      id: :foundation_boundaries,
      module: Workspace.Checks.EnforceBoundaries,
      description: "foundation libraries only depend on foundation libraries",
      opts: [
        tag: {:layer, :foundation},
        allowed_tags: [{:layer, :foundation}]
      ]
    ],
    [
      id: :domain_boundaries,
      module: Workspace.Checks.EnforceBoundaries,
      description: "the domain only depends on foundation libraries",
      opts: [
        tag: {:layer, :domain},
        allowed_tags: [{:layer, :foundation}]
      ]
    ],
    [
      id: :application_boundaries,
      module: Workspace.Checks.EnforceBoundaries,
      description: "applications only depend on the domain and foundation libraries",
      opts: [
        tag: {:layer, :application},
        allowed_tags: [{:layer, :domain}, {:layer, :foundation}]
      ]
    ]
  ]
]
