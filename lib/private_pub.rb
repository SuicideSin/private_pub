require "digest/sha1"
require "net/http"

require "private_pub/faye_extension"
require "private_pub/railtie" if defined? Rails

module PrivatePub
  class Error < StandardError; end

  class << self
    attr_reader :config

    def reset_config
      @config = {
        :server => "http://localhost:9292/faye",
        :signature_expiration => 60 * 60, # one hour
      }
    end

    def load_config(filename, environment)
      yaml = YAML.load_file(filename)[environment.to_s]
      raise ArgumentError, "The #{environment} environment does not exist in #{filename}" if yaml.nil?
      yaml.each { |k, v| config[k.to_sym] = v }
    end

    def ssl?
      uri = URI.parse(@config[:server])
      uri.scheme == "https"
    end

    def subscription(options = {})
      sub = {:timestamp => (Time.now.to_f * 1000).round}.merge(options)
      sub[:signature] = Digest::SHA1.hexdigest([config[:secret_token], sub[:channel], sub[:timestamp]].join)
      sub
    end

    def publish(data)
      url  = URI.parse(@config[:server])
      req  = Net::HTTP::Post.new(url.path)
      req.set_form_data(data)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = ssl?
      res  = http.start { |http| http.request(req) }
    end

    def publish_to(channel, object = nil, &block)
      message = {:channel => channel, :data => {:channel => channel}, :ext => {:private_pub_token => PrivatePub.config[:secret_token]}}
      message[:data][:eval] = capture(&block) if block_given?
      message[:data][:data] = object if object
      PrivatePub.publish(:message => message.to_json)
    end

    def faye_extension
      FayeExtension.new
    end

    def signature_expired?(timestamp)
      timestamp < ((Time.now.to_f - config[:signature_expiration])*1000).round if config[:signature_expiration]
    end
  end

  reset_config
end
