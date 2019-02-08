defmodule NewRelic.Util.Vendor.Fargate do
  @fargate_data ["Cluster", "ImageID", "ImageName", "ContainerID", "ContainerName"]
  @fargate_metadata_env "ECS_CONTAINER_METADATA_FILE"

  def fargate_hash(util, file_path \\ fargate_metadata_file_path()) do
    case File.read(file_path) do
      {:ok, metadata_file_content} ->
        fields =
          Jason.decode!(metadata_file_content)
          |> Map.take(@fargate_data)

        Map.put(util, :vendors, %{aws: fields})

      _error ->
        util
    end
  rescue
    exception ->
      NewRelic.log(:error, "Failed to fetch Fargate metadata file. #{inspect(exception)}")
      util
  end

  defp fargate_metadata_file_path,
    do: System.get_env(@fargate_metadata_env)
end
