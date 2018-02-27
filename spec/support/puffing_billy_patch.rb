# Until https://github.com/oesmith/puffing-billy/pull/228 is released
Billy::RequestHandler.class_exec do
  alias_method :orig_handle_request, :handle_request
  # Avoid Ruby method redefined warning
  remove_method :handle_request
  def handle_request(method, url, headers, body)
    orig_handle_request(method, url, headers, body)
  rescue => error
    { error: error.message }
  end
end
