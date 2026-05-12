#!/usr/bin/env ruby

require_relative 'config/environment'

# Test case 1: Both source_html and body_text are empty
puts "=" * 50
puts "Test 1: Empty source_html and empty body_text"
renderer = News::Translation::HtmlBodyRenderer.new(source_html: "")
result = renderer.call("")
puts "Result: #{result.inspect}"
puts "Result length: #{result.length}"

# Test case 2: Empty source_html with some body_text
puts "\n" + "=" * 50
puts "Test 2: Empty source_html with body_text"
renderer = News::Translation::HtmlBodyRenderer.new(source_html: "")
result = renderer.call("Paragraph one\n\nParagraph two")
puts "Result: #{result}"
puts "Result length: #{result.length}"

# Test case 3: Real source_html with translated body_text
puts "\n" + "=" * 50
puts "Test 3: Real source_html with translated body_text"
source_html = '<p>Original paragraph one</p><p>Original paragraph two</p>'
renderer = News::Translation::HtmlBodyRenderer.new(source_html:)
result = renderer.call("Translated paragraph one\n\nTranslated paragraph two")
puts "Result: #{result}"
puts "Result length: #{result.length}"

# Test case 4: Real source_html with body_text that has fewer paragraphs
puts "\n" + "=" * 50
puts "Test 4: Real source_html with fewer translated paragraphs"
source_html = '<p>Original one</p><p>Original two</p><p>Original three</p>'
renderer = News::Translation::HtmlBodyRenderer.new(source_html:)
result = renderer.call("Translated one")
puts "Result: #{result}"
puts "Result length: #{result.length}"

# Test case 5: Check if body_text without double newlines works
puts "\n" + "=" * 50
puts "Test 5: body_text without double newlines"
source_html = '<p>Original one</p><p>Original two</p>'
renderer = News::Translation::HtmlBodyRenderer.new(source_html:)
result = renderer.call("Translated text on single line")
puts "Result: #{result}"
puts "Result length: #{result.length}"
