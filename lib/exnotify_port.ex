defmodule ExnotifyPort do
  use GenServer

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    opts = Keyword.put_new(opts, :receiver, self())
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def add_watch(server, path) do
    GenServer.call(server, {:add_watch, path})
  end

  def remove(server, path) do
    GenServer.call(server, {:remove, path})
  end

  @impl true
  def init(opts) do
    opts = Keyword.validate!(opts, [:receiver])

    executable = Path.join(:code.priv_dir(:exnotify_port), "inotify")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        packet: 2
      ])

    {:ok,
     %{
       receiver: Keyword.fetch!(opts, :receiver),
       port: port
     }}
  end

  @impl true
  def handle_call({:add_watch, path}, _from, state) do
    reply = send_command(state.port, "add_watch #{path}")
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:remove, path}, _from, state) do
    reply = send_command(state.port, "remove #{path}")
    {:reply, reply, state}
  end

  @impl true
  def handle_info({_port, {:data, <<0::8*8, data::binary>>}}, state) do
    send(state.receiver, data_to_message(JSON.decode!(data)))
    {:noreply, state}
  end

  defp send_command(port, command) do
    id = :erlang.unique_integer([:positive])
    Port.command(port, <<id::8*8-big, command::binary>>)

    receive do
      {^port, {:data, <<^id::8*8-big, data::binary>>}} ->
        data_to_reply(JSON.decode!(data))
    after
      1000 -> {:error, :timeout}
    end
  end

  defp data_to_reply("ok"), do: :ok
  defp data_to_reply(%{"Err" => err}), do: {:error, err}

  defp data_to_message(%{"Name" => name, "Op" => op}), do: {:inotify_event, name, op_symbols(op)}
  defp data_to_message(%{"Err" => err}), do: {:inotify_error, err}

  defp op_symbols(op) do
    <<chmod::1, rename::1, remove::1, write::1, create::1>> = <<op::5>>
    flags = [chmod: chmod, rename: rename, remove: remove, write: write, create: create]

    for {n, 1} <- flags, into: MapSet.new(), do: n
  end
end
