defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  def parse(%{result: {:ok, %{__struct__: Postgrex.Cursor}}}), do: :ignore

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Postgrex.Result, Postgrex.Error] do
    {"Postgres", parse_query(query)}
  end

  def parse(%{result: {:ok, %{__struct__: MyXQL.Cursor}}}), do: :ignore

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [MyXQL.Result, MyXQL.Error] do
    {"MySQL", parse_query(query)}
  end

  def parse(%{
        query: query,
        repo: repo,
        result: {_ok_or_error, %{__struct__: _result_struct}}
      }) do
    [adaapter | _] = repo.__adapter__() |> Module.split() |> Enum.reverse()
    {adaapter, parse_query(query)}
  end

  def parse(%{result: {:ok, _}}), do: :ignore
  def parse(%{result: {:error, _}}), do: :ignore

  # Escape chars
  #   Postgrex: "
  #   MyXQL: `
  #   Tds: [
  #   Exqlite: none
  @esc ~s(["`\[]?)

  @select ~r/FROM #{@esc}(?<table>\w+)#{@esc}/
  @insert ~r/INSERT INTO #{@esc}(?<table>\w+)#{@esc}/
  @update ~r/UPDATE #{@esc}(?<table>\w+)#{@esc}/
  @delete ~r/FROM #{@esc}(?<table>\w+)#{@esc}/
  @create ~r/CREATE TABLE( IF NOT EXISTS)? #{@esc}(?<table>\w+)#{@esc}/
  defp parse_query(query) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@create, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {table, operation}
  end

  defp capture(regex, query, match) do
    Regex.named_captures(regex, query)[match]
  end
end
