# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove this line.
ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = "#{::Rails.root}/spec/fixtures"

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  config.when_first_matching_example_defined(type: :system) do
    require 'capybara'
    require 'selenium/webdriver'
    require 'billy/capybara/rspec'
    require 'support/puffing_billy_patch'

    # @see https://github.com/oesmith/puffing-billy/blob/v0.12.0/lib/billy/browsers/capybara.rb#L57-L65 `selenium_chrome_billy` registration
    ::Capybara.register_driver :custom_selenium_chrome_billy do |app|
      options = Selenium::WebDriver::Chrome::Options.new

      # Run in headless mode
      options.add_argument '--headless'
      options.add_argument '--disable-gpu'

      # Configure headless mode to ignore our local certs
      options.add_argument '--no-sandbox'
      options.add_argument '--disable-web-security'
      options.add_argument '--allow-running-insecure-content'
      options.add_argument '--ignore-certificate-errors'
      options.add_argument '--allow-insecure-localhost'

      # When using puffing-billy custom cache scopes to record variations of
      # the same URL it's possible to get random spec failures due to Chrome's
      # internal cache; which may serve a previous cached version instead.
      #
      # I'm unaware of a way to use a hook to tell the driver to tell chrome to
      # clear the cache. I tried other cache options like `--disable-cache` and
      # `--incognito` but they did not work. The only way I found to prevent
      # the issue is by disabling cache through the disk cache size.
      #
      # Setting the value to 0 does not work either.
      options.add_argument '--disk-cache-size=1'

      options.add_argument "--proxy-server=#{Billy.proxy.host}:#{Billy.proxy.port}"

      capabilities = ::Selenium::WebDriver::Remote::Capabilities.chrome
      capabilities['acceptInsecureCerts'] = true
      capabilities['acceptSslCerts'] = true

      ::Capybara::Selenium::Driver.new(
        app,
        browser: :chrome,
        desired_capabilities: capabilities,
        options: options,
      )
    end

    # Use `prepend_before` to allow specs to override this in `before` hooks
    config.prepend_before(type: :system) do
      driven_by :custom_selenium_chrome_billy
    end

    # Per https://github.com/oesmith/puffing-billy#google-chrome-headless-example
    if ENV['CI']
      # Overwrite the local home directory for chrome. We use this
      # to setup a custom SSL certificate store.
      ENV['HOME'] = "#{Dir.tmpdir}/chrome-home-#{Time.now.to_i}"

      # Clear and recreate the Chrome home directory.
      FileUtils.rm_rf(ENV['HOME'])
      FileUtils.mkdir_p(ENV['HOME'])

      # Setup a new pki certificate database for Chrome
      system <<~SCRIPT
        cd "#{ENV['HOME']}"
        curl -s -k -o "cacert-root.crt" "http://www.cacert.org/certs/root.crt"
        curl -s -k -o "cacert-class3.crt" "http://www.cacert.org/certs/class3.crt"
        echo > .password
        mkdir -p .pki/nssdb
        CERT_DIR=sql:$HOME/.pki/nssdb
        certutil -N -d .pki/nssdb -f .password
        certutil -d ${CERT_DIR}  -A -t TC \
          -n "CAcert.org" -i cacert-root.crt
        certutil -d ${CERT_DIR} -A -t TC \
          -n "CAcert.org Class 3" -i cacert-class3.crt
        certutil -d sql:$HOME/.pki/nssdb -A \
          -n puffing-billy -t "CT,C,C" -i #{Billy.certificate_authority.cert_file}
      SCRIPT
    end
  end

  config.when_first_matching_example_defined(:webmock) do
    require 'webmock/rspec'
    WebMock.disable_net_connect!(allow_localhost: true)

    # NOTE: In a real app I likely would not include this. It is necessary here
    # to ensure the different tests which should not be using WebMock do not
    # have it enabled. Due to threading issues we need to do this early before
    # puma launches; which is why we use `prepend_before`.
    config.prepend_before do |ex|
      if ex.metadata[:webmock]
        WebMock.enable!
        WebMock.disable_net_connect!(allow_localhost: true)
      else
        WebMock.disable!
      end
    end
    config.after do |ex|
      WebMock.disable!
    end
  end

  config.when_first_matching_example_defined(:vcr) do
    require 'support/vcr'

    # NOTE: In a real app I likely would not include this. It is necessary here
    # to ensure the different tests which should not be using VCR do not
    # have it enabled. Due to threading issues we need to do this early before
    # puma launches; which is why we use `prepend_before`.
    config.prepend_before do |ex|
      if ex.metadata[:vcr]
        VCR.turn_on!
      else
        VCR.turn_off!
      end
    end
    config.after do |ex|
      if ex.metadata[:vcr]
        VCR.eject_cassette(skip_no_unused_interactions_assertion: !!ex.exception)
        VCR.turn_off!
      end
    end
  end

  if !system(*%w[ ping -c 10 -o www.github.com ], out: IO::NULL, err: IO::NULL)
    config.before(:example, :online) do
      skip "This example requires the network and we are not currently online."
    end
  end
end
