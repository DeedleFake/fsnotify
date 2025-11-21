defmodule FSNotify.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{id: FSNotify.Subscribers, start: {:pg, :start_link, [FSNotify.Subscribers]}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
