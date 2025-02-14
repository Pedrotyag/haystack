# frozen_string_literal: true

require "spec_helper"
require 'contexts/with_request_mock'

RSpec.describe Haystack::Net::HTTP do
  include_context "with request mock"

  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end

  context "with IPv6 addresses" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "correctly parses the short-hand IPv6 addresses" do
      stub_normal_response

      transaction = Haystack.start_transaction
      Haystack.get_current_scope.set_span(transaction)

      _ = Net::HTTP.get("::1", "/path", 8080)

      expect(transaction.span_recorder.spans.count).to eq(2)

      request_span = transaction.span_recorder.spans.last
      expect(request_span.data).to eq(
        { "url" => "http://[::1]/path", "http.request.method" => "GET", "http.response.status_code" => 200 }
      )
    end
  end

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.transport.transport_class = Haystack::HTTPTransport
        config.logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = 'http://foobarbaz@o447951.ingest.haystack.io/5434472'
      end
    end

    context "with config.send_default_pii = true" do
      before do
        Haystack.configuration.send_default_pii = true
      end

      it "records the request's span with query string in data" do
        stub_normal_response

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))

        expect(response.code).to eq("200")
        expect(transaction.span_recorder.spans.count).to eq(2)

        request_span = transaction.span_recorder.spans.last
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.net_http")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 200,
          "url" => "http://example.com/path",
          "http.request.method" => "GET",
          "http.query" => "foo=bar"
        })
      end
    end

    context "with config.send_default_pii = false" do
      before do
        Haystack.configuration.send_default_pii = false
      end

      it "records the request's span without query string" do
        stub_normal_response

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))

        expect(response.code).to eq("200")
        expect(transaction.span_recorder.spans.count).to eq(2)

        request_span = transaction.span_recorder.spans.last
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.net_http")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 200,
          "url" => "http://example.com/path",
          "http.request.method" => "GET"
        })
      end
    end

    it "supports non-ascii characters in the path" do
      stub_normal_response

      uri = URI('http://example.com')
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new('/path?q=øgreyfoss&å=vær')

      transaction = Haystack.start_transaction
      Haystack.get_current_scope.set_span(transaction)


      response = http.request(request)

      expect(response.code).to eq("200")
    end

    it "adds haystack-trace header to the request header" do
      uri = URI("http://example.com/path")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)

      transaction = Haystack.start_transaction
      Haystack.get_current_scope.set_span(transaction)

      stub_normal_response do |request, _|
        request_span = transaction.span_recorder.spans.last
        expect(request["haystack-trace"]).to eq(request_span.to_haystack_trace)
      end

      response = http.request(request)

      expect(response.code).to eq("200")
    end

    it "adds baggage header to the request header as head SDK when no incoming trace" do
      stub_normal_response

      uri = URI("http://example.com/path")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)

      transaction = Haystack.start_transaction
      Haystack.get_current_scope.set_span(transaction)

      response = http.request(request)

      expect(response.code).to eq("200")
      request_span = transaction.span_recorder.spans.last
      expect(request["baggage"]).to eq(request_span.to_baggage)
      expect(request["baggage"]).to eq(
        "haystack-trace_id=#{transaction.trace_id},"\
        "haystack-sample_rate=1.0,"\
        "haystack-sampled=true,"\
        "haystack-environment=development,"\
        "haystack-public_key=foobarbaz"
      )
    end

    it "adds baggage header to the request header when continuing incoming trace" do
      stub_normal_response

      uri = URI("http://example.com/path")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)

      haystack_trace = "d298e6b033f84659928a2267c3879aaa-2a35b8e9a1b974f4-1"
      baggage = "other-vendor-value-1=foo;bar;baz, "\
        "haystack-trace_id=d298e6b033f84659928a2267c3879aaa, "\
        "haystack-public_key=49d0f7386ad645858ae85020e393bef3, "\
        "haystack-sample_rate=0.01337, "\
        "haystack-user_id=Am%C3%A9lie,  "\
        "other-vendor-value-2=foo;bar;"

      transaction = Haystack.continue_trace({ "haystack-trace" => haystack_trace, "baggage" => baggage })
      Haystack.get_current_scope.set_span(transaction)

      response = http.request(request)

      expect(response.code).to eq("200")
      request_span = transaction.span_recorder.spans.last
      expect(request["baggage"]).to eq(request_span.to_baggage)
      expect(request["baggage"]).to eq(
        "haystack-trace_id=d298e6b033f84659928a2267c3879aaa,"\
        "haystack-public_key=49d0f7386ad645858ae85020e393bef3,"\
        "haystack-sample_rate=0.01337,"\
        "haystack-user_id=Am%C3%A9lie"
      )
    end

    context "with config.propagate_traces = false" do
      before do
        Haystack.configuration.propagate_traces = false
      end

      it "doesn't add the haystack-trace header to outgoing requests" do
        stub_normal_response

        uri = URI("http://example.com/path")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        response = http.request(request)

        expect(response.code).to eq("200")
        expect(request.key?("haystack-trace")).to eq(false)
      end

      it "doesn't add the baggage header to outgoing requests" do
        stub_normal_response

        uri = URI("http://example.com/path")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)

        haystack_trace = "d298e6b033f84659928a2267c3879aaa-2a35b8e9a1b974f4-1"
        baggage = "other-vendor-value-1=foo;bar;baz, "\
          "haystack-trace_id=d298e6b033f84659928a2267c3879aaa, "\
          "haystack-public_key=49d0f7386ad645858ae85020e393bef3, "\
          "haystack-sample_rate=0.01337, "\
          "haystack-user_id=Am%C3%A9lie,  "\
          "other-vendor-value-2=foo;bar;"

        transaction = Haystack.continue_trace({ "haystack-trace" => haystack_trace, "baggage" => baggage })
        Haystack.get_current_scope.set_span(transaction)

        response = http.request(request)

        expect(response.code).to eq("200")
        expect(request.key?("baggage")).to eq(false)
      end
    end

    context "with custom trace_propagation_targets" do
      before do
        Haystack.configuration.trace_propagation_targets = ["example.com", /foobar.org\/api\/v2/]
      end

      it "doesn't add haystack headers to outgoing requests to different target" do
        stub_normal_response

        uri = URI("http://google.com/path")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        http.request(request)

        expect(request.key?("haystack-trace")).to eq(false)
        expect(request.key?("baggage")).to eq(false)
      end

      it "doesn't add haystack headers to outgoing requests to different target path" do
        stub_normal_response

        uri = URI("http://foobar.org/api/v1/path")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        http.request(request)

        expect(request.key?("haystack-trace")).to eq(false)
        expect(request.key?("baggage")).to eq(false)
      end

      it "adds haystack headers to outgoing requests matching string" do
        stub_normal_response

        uri = URI("http://example.com/path")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        http.request(request)

        expect(request.key?("haystack-trace")).to eq(true)
        expect(request.key?("baggage")).to eq(true)
      end

      it "adds haystack headers to outgoing requests matching regexp" do
        stub_normal_response

        uri = URI("http://foobar.org/api/v2/path")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)

        transaction = Haystack.start_transaction
        Haystack.get_current_scope.set_span(transaction)

        http.request(request)

        expect(request.key?("haystack-trace")).to eq(true)
        expect(request.key?("baggage")).to eq(true)
      end
    end

    it "doesn't record span for the SDK's request" do
      stub_haystack_response

      transaction = Haystack.start_transaction
      Haystack.get_current_scope.set_span(transaction)

      Haystack.capture_message("foo")

      # make sure the request was actually made
      expect(string_io.string).to match(/bad haystack DSN public key/)
      expect(transaction.span_recorder.spans.count).to eq(1)
    end

    context "when there're multiple requests" do
      let(:transaction) { Haystack.start_transaction }

      before do
        Haystack.get_current_scope.set_span(transaction)
      end

      def verify_spans(transaction)
        expect(transaction.span_recorder.spans.count).to eq(3)
        expect(transaction.span_recorder.spans[0]).to eq(transaction)

        request_span = transaction.span_recorder.spans[1]
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.net_http")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 200,
          "url" => "http://example.com/path",
          "http.request.method" => "GET"
        })

        request_span = transaction.span_recorder.spans[2]
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.net_http")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 404,
          "url" => "http://example.com/path",
          "http.request.method" => "GET"
        })
      end

      it "doesn't mess different requests' data together" do
        stub_normal_response(code: "200")
        response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))
        expect(response.code).to eq("200")

        stub_normal_response(code: "404")
        response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))
        expect(response.code).to eq("404")

        verify_spans(transaction)
      end

      it "doesn't mess different requests' data together when making multiple requests with Net::HTTP.start" do
        Net::HTTP.start("example.com") do |http|
          stub_normal_response(code: "200")
          request = Net::HTTP::Get.new("/path?foo=bar")
          response = http.request(request)
          expect(response.code).to eq("200")

          stub_normal_response(code: "404")
          request = Net::HTTP::Get.new("/path?foo=bar")
          response = http.request(request)
          expect(response.code).to eq("404")
        end

        verify_spans(transaction)
      end

      context "with nested span" do
        let(:span) { transaction.start_child(op: "child span") }

        before do
          Haystack.get_current_scope.set_span(span)
        end

        it "attaches http spans to the span instead of top-level transaction" do
          stub_normal_response(code: "200")
          response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))
          expect(response.code).to eq("200")

          expect(transaction.span_recorder.spans.count).to eq(3)
          expect(span.parent_span_id).to eq(transaction.span_id)
          http_span = transaction.span_recorder.spans.last
          expect(http_span.parent_span_id).to eq(span.span_id)
        end
      end
    end
  end

  context "without tracing enabled nor http_logger" do
    before do
      perform_basic_setup
    end

    it "adds haystack-trace and baggage headers for tracing without performance" do
      stub_normal_response

      uri = URI("http://example.com/path")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      expect(request["haystack-trace"]).to eq(Haystack.get_traceparent)
      expect(request["baggage"]).to eq(Haystack.get_baggage)
      expect(response.code).to eq("200")
    end

    it "doesn't create transaction or breadcrumbs" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path"))
      expect(response.code).to eq("200")

      expect(Haystack.get_current_scope.get_transaction).to eq(nil)
      expect(Haystack.get_current_scope.breadcrumbs.peek).to eq(nil)
    end
  end

  context "without SDK" do
    it "doesn't affect the HTTP lib anything" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path"))
      expect(response.code).to eq("200")
    end
  end
end
