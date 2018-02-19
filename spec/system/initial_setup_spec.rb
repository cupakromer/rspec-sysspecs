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

end
