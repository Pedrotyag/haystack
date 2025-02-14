# frozen_string_literal: true

require "rake"
require "rake/task"

module Haystack
  module Rake
    module Application
      # @api private
      def display_error_message(ex)
        mechanism = Haystack::Mechanism.new(type: "rake", handled: false)

        Haystack.capture_exception(ex, hint: { mechanism: mechanism }) do |scope|
          task_name = top_level_tasks.join(" ")
          scope.set_transaction_name(task_name, source: :task)
          scope.set_tag("rake_task", task_name)
        end if Haystack.initialized? && !Haystack.configuration.skip_rake_integration

        super
      end
    end
  end
end

# @api private
module Rake
  class Application
    prepend(Haystack::Rake::Application)
  end
end
