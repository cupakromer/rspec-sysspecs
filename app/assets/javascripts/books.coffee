# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$ ->
  $.ajax(
    url: "https://api.github.com",
    jsonp: "callback",
    dataType: "jsonp",
    success: (response) ->
      $("#github").html(JSON.stringify(response))
  );
