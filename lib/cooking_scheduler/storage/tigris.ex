defmodule CookingScheduler.Storage.Tigris do
  @moduledoc """
  Stores files in a Tigris bucket (S3-compatible) using `Req`'s SigV4 signing. The bucket is
  private; the app reads files back with `get/1` and serves them itself. Configured in
  `config/runtime.exs`.
  """
  @behaviour CookingScheduler.Storage

  @impl true
  def put(key, body, content_type) do
    request()
    |> Req.put(url: object_url(key), body: body, headers: [{"content-type", content_type}])
    |> result()
  end

  @impl true
  def delete(key) do
    request()
    |> Req.delete(url: object_url(key))
    |> result()
  end

  @impl true
  def get(key) do
    case Req.get(request(), url: object_url(key), decode_body: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp result({:ok, %{status: status}}) when status in 200..299, do: :ok
  defp result({:ok, %{status: status}}), do: {:error, {:status, status}}
  defp result({:error, reason}), do: {:error, reason}

  defp request do
    config = config()

    Req.new(
      aws_sigv4: [
        access_key_id: config[:access_key_id],
        secret_access_key: config[:secret_access_key],
        service: :s3,
        region: "auto"
      ]
    )
  end

  defp object_url(key) do
    config = config()
    "https://#{config[:bucket]}.#{config[:host]}/#{key}"
  end

  defp config, do: Application.fetch_env!(:cooking_scheduler, __MODULE__)
end
