$:.unshift File.dirname(__FILE__)

require 'rubygems'
require 'rack'

class Capone
  class << self
    
    def app &block
      Capone::Application.new(&block)
    end

  end
end

class Capone #:nodoc:

  class Application

    attr_reader :routes, :responder_class, :middlewares

    def initialize &block
      set_defaults
      instance_eval &block  
    end

    def add_route http_method, matcher, block
      if matcher.is_a? String
        named_captures = matcher.scan(/:(\w+)/)
        unless named_captures.empty?
          matcher = Regexp.new(matcher.gsub(/:(\w+)/, '(\w+)'))
          eval "def matcher.named_captures
            #{ named_captures.map {|arr| arr.first }.inspect }
          end"
        end
      end
      routes[http_method][matcher] = block
    end

    def get path, &block
      add_route :get, path, block
    end

    def post path, &block
      add_route :post, path, block
    end
    
    def put path, &block
      add_route :put, path, block
    end
    
    def delete path, &block
      add_route :delete, path, block
    end

    def helpers &block
      responder_class.class_eval &block
    end

    def use middlware
      middlewares.unshift middlware
    end

    def call env
      rack_app = lambda { |env|
        http_method = env['REQUEST_METHOD'].downcase.to_sym
        path        = env['PATH_INFO']

        params      = { }
        match       = nil

        matchers = routes[http_method]
        matchers.each do |matcher, block|
          match_data = matcher.match(path)
          if match_data
            params['captures'] = match_data[1..1_000_000]
            if matcher.respond_to? :named_captures
              matcher.named_captures.each_with_index do |key, index|
                params[key] = match_data[index + 1]
              end
            end
            match = block
          end
        end
        
        if match
          responder = responder_class.new env
          responder.params.merge! params
          body = responder.instance_eval &match
          responder.finish(body)
        else
          [ 404, {}, "Route not found!  All Routes: #{ routes.inspect }" ]
        end
      }

      middlewares.each do |middleware|
        rack_app = middleware.new rack_app
      end

      rack_app.call env
    end

    private

    def set_defaults
      @routes          ||= { :get => {}, :post => {}, :put => {}, :delete => {} }
      @responder_class ||= Responder.dup
      @middlewares     ||= []
    end

    class Responder
      attr_reader :request, :response

      def params
        request.params
      end

      def redirect path
        response['Location'] = path
        response.status = 302
      end

      def status code
        response.status = code
      end

      def initialize env
        @request  = Rack::Request.new env
        @response = Rack::Response.new
      end

      def finish body
        response.write body
        response.finish
      end
    end

  end
end
