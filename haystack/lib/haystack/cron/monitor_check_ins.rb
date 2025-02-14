# frozen_string_literal: true

module Haystack
  module Cron
    module MonitorCheckIns
      MAX_SLUG_LENGTH = 50

      module Patch
        def perform(*args, **opts)
          slug = self.class.haystack_monitor_slug
          monitor_config = self.class.haystack_monitor_config

          check_in_id = Haystack.capture_check_in(slug,
                                                :in_progress,
                                                monitor_config: monitor_config)

          start = Metrics::Timing.duration_start

          begin
            # need to do this on ruby <= 2.6 sadly
            ret = method(:perform).super_method.arity == 0 ? super() : super
            duration = Metrics::Timing.duration_end(start)

            Haystack.capture_check_in(slug,
                                    :ok,
                                    check_in_id: check_in_id,
                                    duration: duration,
                                    monitor_config: monitor_config)

            ret
          rescue Exception
            duration = Metrics::Timing.duration_end(start)

            Haystack.capture_check_in(slug,
                                    :error,
                                    check_in_id: check_in_id,
                                    duration: duration,
                                    monitor_config: monitor_config)

            raise
          end
        end
      end

      module ClassMethods
        def haystack_monitor_check_ins(slug: nil, monitor_config: nil)
          if monitor_config && Haystack.configuration
            cron_config = Haystack.configuration.cron
            monitor_config.checkin_margin ||= cron_config.default_checkin_margin
            monitor_config.max_runtime ||= cron_config.default_max_runtime
            monitor_config.timezone ||= cron_config.default_timezone
          end

          @haystack_monitor_slug = slug
          @haystack_monitor_config = monitor_config

          prepend Patch
        end

        def haystack_monitor_slug(name: self.name)
          @haystack_monitor_slug ||= begin
            slug = name.gsub("::", "-").downcase
            slug[-MAX_SLUG_LENGTH..-1] || slug
          end
        end

        def haystack_monitor_config
          @haystack_monitor_config
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end
    end
  end
end
