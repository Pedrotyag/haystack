# frozen_string_literal: true

require 'spec_helper'

return unless defined?(SidekiqScheduler::Scheduler)

RSpec.describe Haystack::SidekiqScheduler::Scheduler do
  before do
    perform_basic_setup { |c| c.enabled_patches += [:sidekiq_scheduler] }
  end

  before do
    schedule_file = 'spec/fixtures/sidekiq-scheduler-schedule.yml'
    config_options = { scheduler: YAML.load_file(schedule_file) }

    # Sidekiq::Scheduler merges it's config with Sidekiq.
    # To grab a config for it to start, we need to pass sidekiq configuration
    # (defaults should be fine though).
    scheduler_config = SidekiqScheduler::Config.new(sidekiq_config: sidekiq_config(config_options))

    # Making and starting a Manager instance will load the jobs
    schedule_manager = SidekiqScheduler::Manager.new(scheduler_config)
    schedule_manager.start
  end

  it 'patches class' do
    expect(SidekiqScheduler::Scheduler.ancestors).to include(described_class)
  end

  it 'patches HappyWorkerForScheduler' do
    expect(HappyWorkerForScheduler.ancestors).to include(Haystack::Cron::MonitorCheckIns)
    expect(HappyWorkerForScheduler.haystack_monitor_slug).to eq('happy')
    expect(HappyWorkerForScheduler.haystack_monitor_config).to be_a(Haystack::Cron::MonitorConfig)
    expect(HappyWorkerForScheduler.haystack_monitor_config.schedule).to be_a(Haystack::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerForScheduler.haystack_monitor_config.schedule.value).to eq('* * * * *')
  end

  it 'patches HappyWorkerForSchedulerWithTimezoneWithTimezone' do
    expect(HappyWorkerForSchedulerWithTimezone.ancestors).to include(Haystack::Cron::MonitorCheckIns)
    expect(HappyWorkerForSchedulerWithTimezone.haystack_monitor_slug).to eq('happy_timezone')
    expect(HappyWorkerForSchedulerWithTimezone.haystack_monitor_config).to be_a(Haystack::Cron::MonitorConfig)
    expect(HappyWorkerForSchedulerWithTimezone.haystack_monitor_config.schedule).to be_a(Haystack::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerForSchedulerWithTimezone.haystack_monitor_config.schedule.value).to eq('* * * * *')
    expect(HappyWorkerForSchedulerWithTimezone.haystack_monitor_config.timezone).to eq('Europe/Vienna')
  end

  it 'does not override SadWorkerWithCron manually set values' do
    expect(SadWorkerWithCron.ancestors).to include(Haystack::Cron::MonitorCheckIns)
    expect(SadWorkerWithCron.haystack_monitor_slug).to eq('failed_job')
    expect(SadWorkerWithCron.haystack_monitor_config).to be_a(Haystack::Cron::MonitorConfig)
    expect(SadWorkerWithCron.haystack_monitor_config.schedule).to be_a(Haystack::Cron::MonitorSchedule::Crontab)
    expect(SadWorkerWithCron.haystack_monitor_config.schedule.value).to eq('5 * * * *')
  end

  it "sets correct monitor config based on `every` schedule" do
    expect(EveryHappyWorker.ancestors).to include(Haystack::Cron::MonitorCheckIns)
    expect(EveryHappyWorker.haystack_monitor_slug).to eq('regularly_happy')
    expect(EveryHappyWorker.haystack_monitor_config).to be_a(Haystack::Cron::MonitorConfig)
    expect(EveryHappyWorker.haystack_monitor_config.schedule).to be_a(Haystack::Cron::MonitorSchedule::Interval)
    expect(EveryHappyWorker.haystack_monitor_config.schedule.to_hash).to eq({ value: 10, type: :interval, unit: :minute })
  end

  it "does not add monitors for a one-off job" do
    expect(ReportingWorker.ancestors).not_to include(Haystack::Cron::MonitorCheckIns)
  end

 it 'truncates from the beginning and parameterizes slug' do
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.ancestors).to include(Haystack::Cron::MonitorCheckIns)
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.haystack_monitor_slug).to eq('ongoutermodule-veryveryveryverylonginnermodule-job')
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.haystack_monitor_config).to be_a(Haystack::Cron::MonitorConfig)
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.haystack_monitor_config.schedule).to be_a(Haystack::Cron::MonitorSchedule::Crontab)
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.haystack_monitor_config.schedule.value).to eq('* * * * *')
 end
end
