defmodule Expm.CLI.Command do
  defmacro __using__(_) do
    quote do
      import Expm.CLI.Command
      Module.register_attribute __MODULE__, :command
    end
  end
  defmacro command(pattern, arg, body) do
    command = if pattern == [], do: "<no command>", else: hd(pattern)
    match?({:"<<>>", _, [command|_]},command)
    quote do
      @command {unquote(command), @doc, @shortdoc}
      Module.delete_attribute __MODULE__, :doc
      Module.delete_attribute __MODULE__, :shortdoc
      def(run(unquote(pattern), unquote(arg)), unquote(body))
    end
  end
end
defrecord Expm.CLI, repository: Expm.Repository.HTTP.new.url, username: nil, password: nil,
                    version: false, format: "asis", format_opts: [] do

  use Expm.CLI.Command

  repository_switch_doc = """
  Options:

    --repository URL (-r URL)

  By default, this is [http://expm.co/](http://expm.co/)
  """
  auth_switch_doc = """
    --username USER and --password PASSWORD

  Used when publishing a package to the repository    
  """

  @shortdoc :skip
  @doc """
  $ expm

  Prints out software information

  Currently supported options: --version

  Example:
    expm --version  
  """
  command([], rec) do
    cond do
      rec.version == true ->
        IO.puts Expm.version
      true ->
        run(["help"], rec)
    end
  end
 
  @shortdoc "Server information"
  @doc """
  $ expm server

  Prints server information

  Currently supported options: --version

  Example:
    expm server --version
  
  #{repository_switch_doc}
  """
  command(["server"], rec) do
    cond do
      rec.version == true ->
        IO.puts repo(rec).version
    end
  end

  @shortdoc "List packages"
  @doc """
  $ expm list

  Lists all packages in the repository

  #{repository_switch_doc}
  """
  command(["list"], rec) do
    run(["search", ""], rec)
  end

  @shortdoc "Search packages"
  @doc """
  $ expm search KEYWORD

  Searches all packages that match the KEYWORD. KEYWORD can be a partial regular expression.

  #{repository_switch_doc}
  """
  command(["search", kwd], rec) do
    repo = repo(rec)
    pkgs = Expm.Package.search repo, kwd
    lc pkg inlist pkgs do
      :io.format("~-20ts ~ts~n",[pkg.name, pkg.description])
    end
  end

  @shortdoc "Show package specification"
  @doc """
  $ expm spec[:FIELD] PACKAGE [--format mix|rebar|scm|asis] [--format-opts OPTS]

      Prints out topmost PACKAGE's version's specification.
      If FIELD is specified, only that field is printed.

  $ expm spec[:FIELD] PACKAGE VERSION [--format mix|rebar|scm|asis] [--format-opts OPTS]

      Prints out specific PACKAGE's VERSION's specification.

      If FIELD is specified, only that field is printed.

  #{repository_switch_doc}
  """
  command([<<"spec", field :: binary>>, package], rec) do
    repo = repo(rec)
    pkg = Expm.Package.fetch repo, package
    case pkg do
      :not_found ->
        IO.puts "No such package"
      _ -> 
        IO.puts spec_field(pkg, field, rec)
    end
  end

  def run([<<"spec", field :: binary>>, package, version], rec) do
    repo = repo(rec)
    pkg = Expm.Package.fetch repo, package, version
    case pkg do
      :not_found ->
        IO.puts "No such package"
      _ -> 
        IO.puts spec_field(pkg, field, rec)
    end
  end

  @shortdoc "Package versions"
  @doc """
  $ expm versions
  Prints a list of PACKAGE's versions

  #{repository_switch_doc}
  """
  command(["versions", package], rec) do
    repo = repo(rec)
    lc version inlist Expm.Package.versions(repo, package) do
      IO.puts version
    end
  end

  @shortdoc "Publish a package"
  @doc """
  $ expm publish
 
  Publishes package.exs to the repository
 
  #{repository_switch_doc}
  #{auth_switch_doc}
  """
  command(["publish"], rec) do
    run(["publish", "package.exs"], rec)
  end

  @shortdoc :skip
  @doc """
  $ expm publish [filename.exs]

  Publishes filename.exs to the repository
 
  #{repository_switch_doc}
  #{auth_switch_doc}  
  """
  command(["publish", file], rec) do
    pkg = Expm.Package.read(file)
    IO.inspect pkg.publish(repo(rec))
  end

  @shortdoc "Create new package"
  @doc """
  $ expm new

  Creates a new template for a package in package.exs
  """
  command(["new"], rec) do
    run(["new","package.exs"], rec)
  end

  @shortdoc :skip
  @doc """
  $ expm new [filename.exs]

  Creates a new template for a package in filename.exs
  """
  command(["new", filename], _rec) do
    File.write filename, Expm.Package.file_template([])
  end
  
  @shortdoc :skip
  @doc """
  $ expm help [command]

  Prints documentation on a specific command
  """
  command(["help", command], _rec) do
    lc {:command, [{cmd, doc, _}]} inlist __info__(:attributes), cmd == command do
      IO.puts doc || "No help available"
    end    
  end

  @shortdoc "Help"
  @doc """
  $ expm help

  Prints help information
  """
  command(["help"], _rec) do
    IO.puts "Commands:\n"
    lc {:command, [{cmd, _, shortdoc}]} inlist __info__(:attributes) do
      unless shortdoc == :skip do
        :io.format("~-20ts ~ts~n",[cmd, shortdoc || ""])
      end
    end
  end

  defp spec_field(pkg, "", rec), do: do_format(pkg, rec)
  defp spec_field(pkg, <<":", field :: binary>>, _rec) do
   field = binary_to_atom field
   inspect apply(pkg,field,[])
  end

  defp formats, do: [
                     {"mix", Expm.Package.Format.Mix},
                     {"rebar", Expm.Package.Format.Rebar},
                     {"scm", Expm.Package.Format.SCM},
                     {"asis", Expm.Package.Format.Asis},
                    ]
  defp do_format(pkg, rec) do
    format = format(rec)
    {format_opts, _} = Code.eval format_opts(rec)
    formatter = :proplists.get_value(String.downcase(format), formats, Expm.Package.Format.Asis)
    apply(formatter, :to_binary, [apply(formatter,:format, [pkg, format_opts])])
  end

  defp repo(rec) do
     Expm.Repository.HTTP.new(url: repository(rec),
                              username: username(rec), password: password(rec))
  end
end
