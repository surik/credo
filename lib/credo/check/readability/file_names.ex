defmodule Credo.Check.Readability.FileNames do
  use Credo.Check,
    base_priority: :high,
    explanations: [
      check: """
      TODO
      """
    ]

  alias Credo.Code.Name

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:defmodule, _meta, arguments} = ast, issues, issue_meta) do
    {ast, issues_for_def(arguments, issues, issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issues_for_def(body, issues, issue_meta) do
    case Enum.at(body, 0) do
      {:__aliases__, meta, names} ->
        names
        |> Enum.filter(&String.Chars.impl_for/1)
        |> Enum.join(".")
        |> issues_for_name(meta, issues, issue_meta)

      _ ->
        issues
    end
  end

  defp issues_for_name(name, meta, issues, issue_meta) do
    splitted_name =
      name
      |> to_string
      |> String.split(".")

    filename =
      Credo.IssueMeta.source_file(issue_meta)
      |> Map.get(:filename)

    splitted_filename =
      filename
      |> String.trim_trailing(".ex")
      |> String.split("/")
      |> Enum.take(-1 * length(splitted_name))
      |> Enum.map(&Macro.camelize/1)

    match_filename? = Path.extname(filename) == ".exs" or splitted_filename == splitted_name

    if match_filename? do
      issues
    else
      [issue_for(issue_meta, meta[:line], name) | issues]
    end
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message: "Module name should match file name",
      trigger: trigger,
      line_no: line_no
    )
  end
end
