# frozen_string_literal: true

require 'yard'

task default: [:doc]

YARD::Rake::YardocTask.new :doc do |t|
    t.files   = ['modules/**/*.rb']
    t.options = ['--no-private']
end
