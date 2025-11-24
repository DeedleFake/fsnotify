defmodule FSNotify.Supervisor do
  @moduledoc false

  use Supervisor, restart: :transient

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    name = opts[:name]

    children = [
      {Registry, name: registry_name(name), keys: {:duplicate, :pid}},
      {FSNotify.Monitor, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one, auto_shutdown: :all_significant)
  end

  def registry_name(name) do
    Module.concat(name, FSNotify.Registry)
  end
end
