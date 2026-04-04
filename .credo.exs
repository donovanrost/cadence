%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "mix.exs",
          "config/",
          "apps/*/mix.exs",
          "apps/*/lib/",
          "apps/*/test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/", ~r"/cover/"]
      }
    }
  ]
}
