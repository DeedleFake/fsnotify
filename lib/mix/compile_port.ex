defmodule Mix.Tasks.Compile.CompilePort do
  use Mix.Task.Compiler

  @go_path System.find_executable("go")
  @output_path Path.join(:code.priv_dir(:fsnotify), "fsnotify")

  @impl true
  def run(_opts) do
    go(["build", "-v", "-o", @output_path, "./port"])
  end

  @impl true
  def clean() do
    File.rm!(@output_path)
  end

  defp go(args) do
    {_, 0} = System.cmd(@go_path, args)
    :ok
  end
end
