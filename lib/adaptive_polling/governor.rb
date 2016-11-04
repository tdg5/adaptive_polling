require "redis"

module AdaptivePolling
  class Governor
    COEFFICIENT_SUFFIX = ":co".freeze
    LOCK_SUFFIX = ":lock".freeze
    BASE_NAMESPACE = "rb:ap:".freeze

    attr_reader :correction_algorithm, :id, :redis_client

    def initialize(id, correction_algorithm, opts = {})
      @id = id
      @correction_algorithm = correction_algorithm
      @redis_client = opts[:redis_client] || build_default_redis_client
    end

    def calculate_interval_in_ms
      interval = correction_algorithm.call(correction_coefficient).to_i
      interval > 0 ? interval : 1
    end

    def correction_coefficient
      redis_client.get(correction_coefficient_key).to_f
    end

    def correction_coefficient_key
      namespace.concat(COEFFICIENT_SUFFIX)
    end

    def decrement_correction_coefficient
      redis_client.decr(correction_coefficient_key)
    end

    def increment_correction_coefficient
      redis_client.incr(correction_coefficient_key)
    end

    def lock_key
      namespace.concat(LOCK_SUFFIX)
    end

    def namespace
      BASE_NAMESPACE + id
    end

    def try_lock
      raise ArgumentError, "block required" unless block_given?
      ttl_ms = calculate_interval_in_ms
      success = redis_client.set(lock_key, true, :nx => true, :px => ttl_ms)
      return false if !success
      yield(self)
      true
    end

    private

    def build_default_redis_client
      Redis.new
    end
  end
end
