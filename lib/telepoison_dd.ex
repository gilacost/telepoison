defmodule TelepoisonDD do
  @moduledoc """
  OpenTelemetry-instrumented wrapper around HTTPoison.Base

  A client request span is created on request creation, and ended once we get the response.
  http.status and other standard http span attributes are set automatically.
  """

  use HTTPoison.Base
  require OpenTelemetry
  require OpenTelemetry.Tracer
  alias OpenTelemetry.{Span, Tracer}
  require Record

  alias HTTPoison.Request

  @doc """
  Setups the opentelemetry instrumentation for Telepoison

  You should call this method on your application startup, before Telepoison is used.
  """
  def setup do
    OpenTelemetry.register_application_tracer(:telepoison)
  end

  def process_request_headers(headers) when is_map(headers) do
    headers
    |> Enum.into([])
    |> process_request_headers()
  end

  def process_request_headers(headers) when is_list(headers) do
    :otel_propagator.text_map_inject(headers)
  end

  def request(%Request{options: opts} = request) do
    span_name = Keyword.get_lazy(opts, :ot_span_name, fn -> compute_default_span_name(request) end)
    IO.inspect(request, label: RequestOpts)

    attributes =
      ([
         {"http.method", request.method},
         {"http.url", request.url}
       ] ++ Keyword.get(opts, :ot_attributes, []))
      |> IO.inspect(label: AttributenInTelepoison)

    new_ctx = OpenTelemetry.Tracer.start_span(span_name, %{attributes: attributes})

    _ = Tracer.set_current_span(new_ctx)

    super(%{request | headers: []})
  end

  def process_response_status_code(status_code) do
    span_ctx = Tracer.current_span_ctx()
    Span.set_attribute(span_ctx, "http.status_code", status_code)
    # TODO: transform http status in http client span status and set in span
    # https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/semantic_conventions/http.md#status
    OpenTelemetry.Tracer.end_span() |> IO.inspect(label: SpanIsEnded)
    status_code
  end

  def compute_default_span_name(request) do
    method_str = request.method |> Atom.to_string() |> String.upcase()
    %URI{authority: authority} = request.url |> process_request_url() |> URI.parse()
    "#{method_str} #{authority}"
  end
end
