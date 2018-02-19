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

    describe "stubbing client side JSONP requests made by the browser" do
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
        expect(find("#github")).to have_content("gists_url")
      end
    end

    describe "stubbing browser redirects" do
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

    describe "recording / playing back requests", :aggregate_failures do
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

  context "using puffing-billy with webmock"

  context "using puffing-billy with vcr (hooked into webmock)"

end
