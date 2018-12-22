MyApp::Application.configure do
  # Add Rack::LiveReload to the bottom of the middleware stack with the default options:
  config.middleware.insert_after ActionDispatch::Static, Rack::LiveReload
end
