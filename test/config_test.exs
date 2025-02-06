defmodule ConfigTest do
  use ExUnit.Case

  test "Version read from file" do
    assert NewRelic.Config.agent_version() == Mix.Project.config()[:version]
  end

  test "Logger output device" do
    inital_logger = NewRelic.Logger.initial_logger()
    TestHelper.run_with(:nr_config, log: "stdout")

    assert :stdio == NewRelic.Logger.initial_logger()

    TestHelper.run_with(:nr_config, log: "some_file.log")
    assert {:file, "some_file.log"} == NewRelic.Logger.initial_logger()

    TestHelper.run_with(:nr_config, log: "Logger")
    assert :logger == NewRelic.Logger.initial_logger()

    assert inital_logger == NewRelic.Logger.initial_logger()
  end

  test "hydrate automatic attributes" do
    System.put_env("ENV_VAR_NAME", "env-var-value")

    TestHelper.run_with(:application_config,
      automatic_attributes: [
        env_var: {:system, "ENV_VAR_NAME"},
        function_call: {String, :upcase, ["fun"]},
        raw: "attribute"
      ]
    )

    assert NewRelic.Init.determine_automatic_attributes() == %{
             env_var: "env-var-value",
             raw: "attribute",
             function_call: "FUN"
           }
  end

  test "Can configure error collecting via ENV and Application" do
    on_exit(fn ->
      System.delete_env("NEW_RELIC_ERROR_COLLECTOR_ENABLED")
      Application.delete_env(:new_relic_agent, :error_collector_enabled)
      NewRelic.Init.init_features()
    end)

    # Via ENV
    System.put_env("NEW_RELIC_ERROR_COLLECTOR_ENABLED", "false")
    NewRelic.Init.init_features()
    refute NewRelic.Config.feature?(:error_collector)

    # Via Application
    System.delete_env("NEW_RELIC_ERROR_COLLECTOR_ENABLED")
    Application.put_env(:new_relic_agent, :error_collector_enabled, true)
    NewRelic.Init.init_features()
    assert NewRelic.Config.feature?(:error_collector)

    # ENV over Application
    System.put_env("NEW_RELIC_ERROR_COLLECTOR_ENABLED", "true")
    Application.put_env(:new_relic_agent, :error_collector_enabled, false)
    NewRelic.Init.init_features()
    assert NewRelic.Config.feature?(:error_collector)

    # Default
    System.delete_env("NEW_RELIC_ERROR_COLLECTOR_ENABLED")
    Application.delete_env(:new_relic_agent, :error_collector_enabled)
    NewRelic.Init.init_features()
    assert NewRelic.Config.feature?(:error_collector)
  end

  test "Parse multiple app names" do
    assert "Two" in NewRelic.Init.parse_app_names("One; Two")
    assert length(NewRelic.Init.parse_app_names("One; Two")) == 2

    assert length(NewRelic.Init.parse_app_names("One Name")) == 1
  end

  test "Parse labels" do
    labels = NewRelic.Init.parse_labels("key1:value1;key2:value2; key3 :value3;stray ")

    assert ["key3", "value3"] in labels
    assert length(labels) == 3

    assert [] == NewRelic.Init.parse_labels(nil)
  end
end
