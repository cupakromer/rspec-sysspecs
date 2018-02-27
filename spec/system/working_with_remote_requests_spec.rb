require 'rails_helper'

RSpec.describe "System specs", type: :system do

  before do
    Book.create! title: "Any Book Title"
    Book.create! title: "Another Book Title"
  end

  around do |ex|
    # Ensure we use the default config unless modified by the context / spec
    Billy.config.reset
    ex.call
    Billy.config.reset
  end

  context "using only puffing-billy" do
    it "doesn't interfer with puma threading" do
      visit books_url

      expect(page).to have_content(
        "Any Book Title"
      ).and have_content(
        "Another Book Title"
      )
    end

    describe "stubbing requests made by the spec" do
      it "supports HTTP" do
        # NOTE: Using `visit` here requires the port otherwise the system tests
        # plugin will add it to direct it to the test Rails puma server
        proxy.stub('http://www.google.com/').and_return(text: "I'm not Google!")
        visit 'http://www.google.com:80/'
        expect(page).to have_content("I'm not Google!")
      end

      it "supports secure HTTPS" do
        # NOTE: Using `visit` here requires the port otherwise the system tests
        # plugin will add it to direct it to the test Rails puma server
        proxy.stub('https://www.google.com:443/')
             .and_return(text: "I'm not Google SSL!")
        visit 'https://www.google.com:443'
        expect(page).to have_content("I'm not Google SSL!")
      end

      it "requires the port for secure HTTPS", :online do
        # NOTE: Using `visit` here requires the port otherwise the system tests
        # plugin will add it to direct it to the test Rails puma server
        #
        # NOTE: Stubbing only `https://www.google.com/` does not work. The SSL
        # port must be included!
        proxy.stub('https://www.google.com/').and_return(text: "I'm no port!")
        visit 'https://www.google.com:443'
        expect(page).to have_field("q", type: "text")
      end
    end

    describe "stubbing client side JSONP requests made by the browser", :skip do
      it "behaves like normal HTTP/HTTPS stubbing" do
        proxy.stub("https://api.github.com:443/")
             .and_return(jsonp: "I am not Github SSL!")
        visit books_url
        expect(find("#github")).to have_content("I am not Github SSL!")
      end

      it "requires the port for secure HTTPS", :online do
        proxy.stub("https://api.github.com/")
             .and_return(jsonp: "I am not Github SSL!")
        visit books_url
        expect(find("#github")).to have_content(
          "gists_url"
        ).or have_content(
          "API rate limit exceeded"
        )
      end
    end

    describe "stubbing browser redirects", :skip do
      it "behaves like normal HTTP/HTTPS stubbing", :aggregate_failures do
        proxy.stub("http://www.example.com/").and_return(text: "I am a stub!")
        visit books_url
        click_link "New Redirect Book"
        expect(page).to have_content "I am a stub!"

        proxy.stub("https://www.example.com:443/")
             .and_return(text: "I am a stub!")
        visit books_url
        click_link "New SSL Book"
        expect(page).to have_content "I am a stub!"
      end

      it "requires the port for secure HTTPS", :online do
        proxy.stub("https://www.example.com/").and_return(text: "I am a stub!")
        visit books_url
        click_link "New SSL Book"
        expect(page).to have_content(
          "Example Domain"
        ).and have_content(
          "This domain is established to be used for illustrative examples" \
          " in documents."
        )
      end
    end

    specify "stubbing server side network requests does not work", :online do
      proxy.stub("http://www.example.com/").and_return(text: "I am a stub!")
      proxy.stub("http://www.example.com:80/").and_return(text: "I am a port stub!")
      visit books_url
      click_button "All Books"
      expect(find("#serverjs")).to have_content(
        "Example Domain"
      ).and have_content(
        "This domain is established to be used for illustrative examples" \
        " in documents."
      )
    end

    describe "recording / playing back requests", :skip, :aggregate_failures do
      before do |ex|
        # Configure VCR like caching
        Billy.configure do |c|
          # NOTE: To add new caches set `non_whitelisted_requests_disabled` to `false
          c.non_whitelisted_requests_disabled = true
          c.cache = true
          c.cache_request_headers = false
          c.dynamic_jsonp = true
          c.dynamic_jsonp_keys = %w[ callback _ ]
          c.persist_cache = true
          c.ignore_cache_port = true # defaults to true
          c.non_successful_cache_disabled = false
          c.non_successful_error_level = :warn
          c.cache_path = 'spec/req_cache/'
          c.cache_request_body_methods = ['post', 'patch', 'put'] # defaults to ['post']
        end

        driven_by :custom_selenium_chrome_billy
      end

      around do |ex|
        Billy.proxy.cache.with_scope ex.metadata[:cache_scope], &ex
      end

      it "shares caches by default", cache_scope: "shared" do
        visit 'http://www.example.com:80/'
        expect(page).to have_content("Custom shared HTTP example.com cache")
        visit books_url
        click_link "New Redirect Book"
        expect(page).to have_content("Custom shared HTTP example.com cache")

        visit 'https://www.example.com:443/'
        expect(page).to have_content("Custom shared SSL HTTPS example.com cache")
        visit books_url
        click_link "New SSL Book"
        expect(page).to have_content("Custom shared SSL HTTPS example.com cache")
      end

      it "supports custom cache locations", cache_scope: "more_caches" do
        visit books_url
        click_link "New Redirect Book"
        expect(page).to have_content "Separate HTTP cache"

        visit books_url
        click_link "New SSL Book"
        expect(page).to have_content "Separate SSL HTTPS cache"
      end

      it "handles requests made by the spec" do
        # NOTE: Using `visit` here requires the port otherwise the system tests
        # plugin will add it to direct it to the test Rails puma server
        visit 'http://www.example.com:80/'
        expect(page).to have_content("Captured example.com request")

        visit 'https://www.example.com:443'
        expect(page).to have_content("Captured SSL example.com request")
      end

      it "handles client side JSONP requests made by the browser" do
        visit books_url
        expect(find("#github")).to have_content("Captured Github API")
      end

      it "handles browser redirects" do
        visit books_url
        click_link "New Redirect Book"
        expect(page).to have_content("Captured example.com request")

        visit books_url
        click_link "New SSL Book"
        expect(page).to have_content("Captured SSL example.com request")
      end

      it "does not handle server side network requests", :online do
        # Ensure we don't hit the network if this behavior changes
        Billy.configure do |c|
          c.non_whitelisted_requests_disabled = true
        end
        visit books_url
        click_button "All Books"
        expect(find("#serverjs")).to have_content(
          "Example Domain"
        ).and have_content(
          "This domain is established to be used for illustrative examples" \
          " in documents."
        )
      end
    end
  end

  context "using puffing-billy with webmock", :skip, :aggregate_failures, :webmock do
    before do
      driven_by :custom_selenium_chrome_billy

      stub_request(:any, /www.gstatic.com/).to_return(status: 200, body: "")
      stub_request(:any, /favicon.ico/).to_return(status: 200, body: "")
      stub_request(:any, /api.github.com/).to_return(status: 200, body: "")
    end

    describe "stubbing requests made by the spec" do
      it "supports HTTP" do
        # NOTE: Using `visit` here requires the port otherwise the system tests
        # plugin will add it to direct it to the test Rails puma server
        stub_request(:any, "www.example.com").to_return(
          body: "This was stubbed by webmock!"
        )
        visit "http://www.example.com:80"
        expect(page).to have_content("This was stubbed by webmock!")
      end

      it "supports secure HTTPS" do
        # NOTE: Using `visit` here requires the port otherwise the system tests
        # plugin will add it to direct it to the test Rails puma server
        stub_request(:any, "https://www.example.com").to_return(
          body: "Webmock SSL HTTPS request stub"
        )
        visit "https://www.example.com:443"
        expect(page).to have_content("Webmock SSL HTTPS request stub")
      end

      it "ignores the port when stubbing with a regexp" do
        stub_request(:any, /www.example.com/).to_return(
          body: "This is a regex stub!"
        )
        visit "http://www.example.com"
        expect(page).to have_content("This is a regex stub!")

        stub_request(:any, /www.example.com/).to_return(
          body: "This is an SSL regex stub!"
        )
        visit "https://www.example.com"
        expect(page).to have_content("This is an SSL regex stub!")
      end
    end

    it "supports stubbing client side JSONP requests made by the browser" do
      stub_request(:any, /api.github.com/).to_return { |req|
        /(?<jquery_func>jQuery\d+_\d+)/ =~ req.uri.query
        {
          status: 200,
          body: "#{jquery_func}(\"I am Webmock not Github SSL!\")",
          headers: {
            "Content-Type" => "application/javascript; charset=utf-8"
          }
        }
      }
      visit books_url
      expect(find("#github")).to have_content("I am Webmock not Github SSL!")
    end

    it "supports stubbing browser redirects" do
      stub_request(:any, "http://www.example.com/").to_return(
        body: "I am a stub!"
      )
      visit books_url
      click_link "New Redirect Book"
      expect(page).to have_content "I am a stub!"

      stub_request(:any, "https://www.example.com/").to_return(
        body: "I am an SSL HTTPS stub!"
      )
      visit books_url
      click_link "New SSL Book"
      expect(page).to have_content "I am an SSL HTTPS stub!"
    end

    it "supports stubbing server side network requests" do
      stub_request(:any, "http://www.example.com/").to_return(
        body: "I am a stub!"
      )
      visit books_url
      click_button "All Books"
      expect(find("#serverjs")).to have_content("I am a stub!")
    end

    it "sits behind the puffing-billy stubs" do
      proxy.stub("http://www.example.com/").and_return(
        text: "puffing-billy stub"
      )
      stub_request(:any, "http://www.example.com/").to_return(
        body: "webmock stub"
      )
      visit books_url
      click_link "New Redirect Book"
      expect(page).to have_content "puffing-billy stub"
    end

    it "sits behind the puffing-billy cache" do
      # Configure VCR like caching
      Billy.configure do |c|
        # NOTE: To add new caches set `non_whitelisted_requests_disabled` to `false
        c.non_whitelisted_requests_disabled = true
        c.cache = true
        c.cache_request_headers = false
        c.dynamic_jsonp = true
        c.dynamic_jsonp_keys = %w[ callback _ ]
        c.persist_cache = true
        c.ignore_cache_port = true # defaults to true
        c.non_successful_cache_disabled = false
        c.non_successful_error_level = :warn
        c.cache_path = 'spec/req_cache/'
        c.cache_request_body_methods = ['post', 'patch', 'put'] # defaults to ['post']
      end

      # NOTE: If the requests were not already recorded puffing-billy would
      # attempt to make the request, which webmock would then intercept and
      # return the stub reply
      stub_request(:any, "http://www.example.com/").to_return(
        body: "I am a stub!"
      )
      visit books_url
      click_link "New Redirect Book"
      expect(page).to have_content("Captured example.com request")

      stub_request(:any, "https://www.example.com/").to_return(
        body: "I am an SSL HTTPS stub!"
      )
      visit books_url
      click_link "New SSL Book"
      expect(page).to have_content("Captured SSL example.com request")
    end
  end

  context "using puffing-billy with vcr (hooked into webmock)", :skip, :webmock, :vcr, :aggregate_failures do
    before do
      driven_by :custom_selenium_chrome_billy

      Billy.configure do |c|
        # We don't want puffing-billy to block VCR
        c.non_whitelisted_requests_disabled = false
      end

      stub_request(:any, /www.gstatic.com/).to_return(status: 200, body: "")
      stub_request(:any, /favicon.ico/).to_return(status: 200, body: "")
    end

    it "handles requests made by the spec" do
      # NOTE: Using `visit` here requires the port otherwise the system tests
      # plugin will add it to direct it to the test Rails puma server
      visit 'http://www.example.com:80/'
      expect(page).to have_content("VCR recorded example.com request")

      visit 'https://www.example.com:443'
      expect(page).to have_content("VCR recorded SSL example.com request")
    end

    it "handles client side JSONP requests made by the browser" do
      visit books_url
      expect(find("#github")).to have_content("Captured Github API")
    end

    it "handles browser redirects" do
      visit books_url
      click_link "New Redirect Book"
      expect(page).to have_content("Captured example.com request")

      visit books_url
      click_link "New SSL Book"
      expect(page).to have_content("Captured SSL example.com request")
    end

    it "handles server side network requests" do
      visit books_url
      click_button "All Books"
      expect(find("#serverjs")).to have_content(
        "Captured server side request"
      )
    end

    it "sits behind the puffing-billy stubs" do
      proxy.stub("http://www.example.com/").and_return(
        text: "puffing-billy stub"
      )
      visit books_url
      click_link "New Redirect Book"
      expect(page).to have_content "puffing-billy stub"
    end

    it "sits behind the puffing-billy cache" do
      # Configure VCR like caching
      Billy.configure do |c|
        # NOTE: To add new caches set `non_whitelisted_requests_disabled` to `false
        c.non_whitelisted_requests_disabled = true
        c.cache = true
        c.cache_request_headers = false
        c.dynamic_jsonp = true
        c.dynamic_jsonp_keys = %w[ callback _ ]
        c.persist_cache = true
        c.ignore_cache_port = true # defaults to true
        c.non_successful_cache_disabled = false
        c.non_successful_error_level = :warn
        c.cache_path = 'spec/req_cache/'
        c.cache_request_body_methods = ['post', 'patch', 'put'] # defaults to ['post']
      end

      visit books_url
      click_link "New Redirect Book"
      expect(page).to have_content("Captured example.com request")

      visit books_url
      click_link "New SSL Book"
      expect(page).to have_content("Captured SSL example.com request")
    end
  end

end
