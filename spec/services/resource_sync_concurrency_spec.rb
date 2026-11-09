require "rails_helper"
require "timeout"
require "securerandom"

RSpec.describe "ResourceSync concurrent calls", type: :model do
  # Workers need committed setup and independent transactions/connections.
  self.use_transactional_tests = false

  def wait_for_signal(queue)
    Timeout.timeout(10) { queue.pop }
  end

  def wait_for_database_block(connection, waiting_pid, blocking_pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      blocked = connection.select_value(
        "SELECT #{Integer(blocking_pid)} = ANY(pg_blocking_pids(#{Integer(waiting_pid)}))"
      )
      return if blocked
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "The second sync did not wait for the first sync's database lock."
      end
      sleep 0.01
    end
  end

  [ "ec2", "s3" ].each do |service|
    it "serializes overlapping #{service.upcase} syncs and creates one resource" do
      workers = []
      release_first = Queue.new
      first_ready = Queue.new
      second_ready = Queue.new
      results = Queue.new
      environment = Environment.create!(
        name: "RSpec concurrency #{SecureRandom.hex(8)}",
        provider: "aws", region: "us-east-1"
      )
      environment_id = environment.id
      attributes = {
        provider: "aws", service: service, resource_id: "concurrent-#{service}",
        name: "Concurrent resource", region: service == "ec2" ? "us-east-1" : nil,
        metadata: {}
      }.freeze

      # Keep the first sync's writes uncommitted, retaining its real row lock.
      # No locking methods are stubbed or replaced in either worker.
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute("SET LOCAL statement_timeout = '15s'")
            counts = ResourceSync.new(environment: Environment.find(environment_id)).call(resources: [ attributes ])
            first_ready << connection.select_value("SELECT pg_backend_pid()")
            Timeout.timeout(15) { release_first.pop }
            results << counts
          end
        end
      rescue StandardError => error
        results << error
        first_ready << error
      end

      first_pid = wait_for_signal(first_ready)
      raise first_pid if first_pid.is_a?(Exception)

      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute("SET LOCAL statement_timeout = '15s'")
            second_environment = Environment.find(environment_id)
            second_ready << connection.select_value("SELECT pg_backend_pid()")
            results << ResourceSync.new(environment: second_environment).call(resources: [ attributes ])
          end
        end
      rescue StandardError => error
        results << error
        second_ready << error
      end

      second_pid = wait_for_signal(second_ready)
      raise second_pid if second_pid.is_a?(Exception)
      expect(second_pid).not_to eq(first_pid)

      ActiveRecord::Base.connection_pool.with_connection do |connection|
        wait_for_database_block(connection, second_pid, first_pid)
      end
      release_first << true
      workers.each do |worker|
        raise "Concurrent sync did not finish within 20 seconds." unless worker.join(20)
      end

      outcomes = Array.new(results.size) { results.pop }
      failure = outcomes.find { |outcome| outcome.is_a?(Exception) }
      raise failure if failure
      expect(outcomes).to contain_exactly({ created: 1, updated: 0 }, { created: 0, updated: 0 })

      resources = Resource.where(environment_id: environment_id)
      expect(resources.count).to eq(1)
      expect(resources.first.attributes.slice(*attributes.keys.map(&:to_s))).to eq(attributes.stringify_keys)
    ensure
      # Always release and stop workers before deleting this example's rows.
      release_first << true if release_first
      workers&.each do |worker|
        unless worker.join(20)
          worker.kill
          worker.join
        end
      end
      if environment&.persisted?
        Resource.where(environment_id: environment.id).delete_all
        Environment.where(id: environment.id).delete_all
      end
    end
  end
end
