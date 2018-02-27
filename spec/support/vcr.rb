require 'webmock'
require 'vcr'

module JsonpVcrConfig
  def dynamic_jsonp(*params)
    default_cassette_options[:match_requests_on].delete(:uri)
    default_cassette_options[:match_requests_on] << VCR.request_matchers.uri_without_param(*params)

    params = params.map(&:to_s)
    params.each do |name|
      define_cassette_placeholder("<JQUERY_#{name.upcase}>") do |interaction|
        uri = URI.parse(interaction.request.uri)
        CGI.parse(uri.query.to_s)[name]&.first
      end
    end

    ::WebMock.after_request(real_requests_only: false) do |request, response|
      unless VCR.library_hooks.disabled?(:webmock)
        uri = URI.parse(request.uri)
        query = CGI.parse(uri.query.to_s)
        params.each do |name|
          next unless callback_value = query[name]&.first
          response.body.gsub!(
            /#{Regexp.escape("<JQUERY_#{name.upcase}>")}/,
            callback_value,
          )
        end
      end
    end
  end
end

::WebMock.after_request(real_requests_only: false) do |request, response|
  # Issue: https://github.com/vcr/vcr/issues/615
  if response.headers && %w[ gzip deflate ].include?(response.headers['Content-Encoding'])
    response.headers.delete('Content-Encoding')
  end
end

VCR.configure do |c|
  c.extend JsonpVcrConfig

  c.cassette_library_dir = 'spec/cassettes'
  c.hook_into :webmock
  c.ignore_localhost = true
  c.default_cassette_options = {
    record: :once,
    update_content_length_header: true,
  }
  c.dynamic_jsonp :_, :callback
  c.configure_rspec_metadata!
end
