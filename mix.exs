defmodule FSNotify.MixProject do
  use Mix.Project

  @github "https://github.com/DeedleFake/fsnotify"

  def project do
    [
      app: :fsnotify,
      version: "0.2.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers() ++ [:compile_port],
      name: "FSNotify",
      source_url: @github,
      dialyzer: dialyzer(),
      description: description(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix]
    ]
  end

  defp description do
    """
    Port-based cross-platform filesystem watching in the vein of inotify.
    """
  end

  defp package do
    [
      links: %{"GitHub" => @github},
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE go.* port)
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.39.1", only: :dev, runtime: false, warn_if_outdated: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
