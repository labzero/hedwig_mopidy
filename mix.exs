defmodule HedwigMopidy.Mixfile do
  use Mix.Project

  def project do
    [
      app: :hedwig_mopidy,
      version: "0.0.2",
      elixir: ">= 1.3.1",
      deps: deps(),
      description: description(),
      package: package(),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      docs: [main: HedwigMopidy]
    ]
  end

  def application do
    [
      applications: [
        :hedwig,
        :logger,
        :mopidy,
        :httpoison,
        :cowboy,
        :plug
      ],
      mod: {HedwigMopidy, []}
    ]
  end

  defp deps do
    [
      {:hedwig, "~> 1.0"},
      {:mopidy, github: "labzero/mopidy"},
      {:httpoison, "~> 1.0"},
      {:hedwig_brain, github: "labzero/hedwig_brain"},
      {:cowboy, "~> 1.0"},
      {:plug, "~> 1.5.0"}
    ]
  end

  defp description do
    """
    A Mopidy responder for Hedwig
    """
  end

  defp package do
    [
      maintainers: ["Tres Trantham"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/trestrantham/hedwig_mopidy"}
    ]
  end
end
