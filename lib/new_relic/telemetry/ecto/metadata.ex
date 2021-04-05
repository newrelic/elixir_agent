defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  def parse(%{result: {:ok, %{__struct__: Postgrex.Cursor}}}), do: :ignore

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Postgrex.Result, Postgrex.Error] do
    parse_query(query, :postgrex)
  end

  def parse(%{result: {:ok, %{__struct__: MyXQL.Cursor}}}), do: :ignore

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [MyXQL.Result, MyXQL.Error] do
    parse_query(query, MyXQL)
  end

  def parse(
        %{
          query: query,
          repo: repo,
          result: {_ok_or_error, %{__struct__: _result_struct}}
        } = stuff
      ) do
    parse_query(query, repo.__adapter__())
  end

  def parse(%{result: {:ok, _}}), do: :ignore
  def parse(%{result: {:error, _}}), do: :ignore

  @postgrex_select ~r/FROM "(?<table>\w+)"/
  @postgrex_insert ~r/INSERT INTO "(?<table>\w+)"/
  @postgrex_update ~r/UPDATE "(?<table>\w+)"/
  @postgrex_delete ~r/FROM "(?<table>\w+)"/
  @postgrex_create_table ~r/CREATE TABLE( IF NOT EXISTS)? "(?<table>\w+)"/
  defp parse_query(query, :postgrex) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@postgrex_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@postgrex_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@postgrex_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@postgrex_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@postgrex_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"Postgres", table, operation}
  end

  @myxql_select ~r/FROM `(?<table>\w+)`/
  @myxql_insert ~r/INSERT INTO `(?<table>\w+)`/
  @myxql_update ~r/UPDATE `(?<table>\w+)`/
  @myxql_delete ~r/FROM `(?<table>\w+)`/
  @myxql_create_table ~r/CREATE TABLE( IF NOT EXISTS)? `(?<table>\w+)`/
  defp parse_query(query, MyXQL) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@myxql_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@myxql_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@myxql_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@myxql_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@myxql_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"MySQL", table, operation}
  end

  @general_select ~r/FROM (?<table>\w+)/
  @general_insert ~r/INSERT INTO (?<table>\w+)/
  @general_update ~r/UPDATE (?<table>\w+)/
  @general_delete ~r/FROM (?<table>\w+)/
  @general_create_table ~r/CREATE TABLE( IF NOT EXISTS)? (?<table>\w+)/
  defp parse_query(query, adapter) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@general_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@general_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@general_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@general_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@general_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    [adapter_name | _] = adapter |> Module.split() |> Enum.reverse()
    {adapter_name, table, operation}
  end

  defp capture(regex, query, match) do
    Regex.named_captures(regex, query)[match]
  end
end
