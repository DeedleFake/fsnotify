defmodule FSNotify.MixProject do
  use Mix.Project

  def project do
    [
      app: :fsnotify,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers() ++ [:compile_port],
      name: "FSNotify",
      source_url: "https://github.com/DeedleFake/fsnotify",
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
    Provides cross-platform filesystem event monitoring in the vein of inotify.
    """
  end

  defp package do
    [
      licenses: ["MIT"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
