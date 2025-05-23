defmodule Challenge.MixProject do
  use Mix.Project

  def project do
    [
      app: :challenge,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      files_to_include: [
        "priv/demo_priv.pem",
        "priv/demo_pub.pem"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :public_key, :crypto],
      mod: {Challenge.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      #  Keep only Credo for development (to be removed before submission)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
