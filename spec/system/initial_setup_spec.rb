require 'rails_helper'

RSpec.describe "System specs", type: :system do

  specify "are setup and working" do
    Book.create! title: "Any Book Title"
    Book.create! title: "Another Book Title"

    visit books_url

    expect(page).to have_content(
      "Any Book Title"
    ).and have_content(
      "Another Book Title"
    )
  end

  specify "support JSONP requests", :online do
    visit books_url
    expect(find("#github")).to have_content("gists_url")
  end

  specify "allows server side network requests", :online do
    visit books_url
    expect(find("#serverjs")).to be
    click_button "All Books"
    expect(find("#serverjs")).to have_content(
      "Example Domain"
    ).and have_content(
      "This domain is established to be used for illustrative examples" \
      " in documents."
    )
  end

end
