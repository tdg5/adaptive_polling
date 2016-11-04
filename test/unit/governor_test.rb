require "test_helper"

module AdaptivePolling
  class GovernorTest < TestCase
    Subject = AdaptivePolling::Governor
    DUMMY_ALGO = lambda {}

    context "#initialize" do
      subject { Subject }

      context "correction_algorithm" do
        should "require a correction_algorithm" do
          assert_raises(ArgumentError) do
            subject.new("id")
          end
        end

        should "store the given correction_algorithm" do
          algo = DUMMY_ALGO
          instance = subject.new("id", algo)
          assert_equal algo, instance.correction_algorithm
        end
      end

      context "id" do
        should "require an id" do
          assert_raises(ArgumentError) do
            subject.new
          end
        end

        should "store the given id" do
          id = "id"
          instance = subject.new(id, :correction_algo)
          assert_equal id, instance.id
        end
      end

      context "redis_client" do
        should "accept a :redis_client option" do
          dummy_client = Object.new
          instance = subject.new("id", DUMMY_ALGO, :redis_client => dummy_client)
          assert_equal dummy_client, instance.redis_client
        end

        should "generate a default :redis_client if none given" do
          dummy_client = Object.new
          Redis.expects(:new).returns(dummy_client)
          instance = subject.new("id", DUMMY_ALGO)
          assert_equal dummy_client, instance.redis_client
        end
      end
    end

    context "#calculate_interval_in_ms" do
      should "return the result of the correction algorithm when given the correction coefficient" do
        invocation_count = 5
        identity_algo_invocation_count = 0
        identity_algo = lambda do |cc|
          identity_algo_invocation_count += 1
          cc
        end
        instance = Subject.new("id", identity_algo)
        invocation_count.times do |i|
          assert_equal(instance.correction_coefficient, instance.calculate_interval_in_ms)
          instance.increment_correction_coefficient
        end
        assert_equal invocation_count, identity_algo_invocation_count
      end

      should "return 1 if the calculated interval is less than or equal to 0" do
        interval = nil
        instance = Subject.new("id", lambda { |cc| interval })
        [0, -1].each do |bad_interval|
          interval = bad_interval
          assert_equal 1, instance.calculate_interval_in_ms
        end
      end

      should "coerce a float into an integer" do
        interval = 5.0
        instance = Subject.new("id", lambda { |cc| interval })
        assert_equal interval.to_i, instance.calculate_interval_in_ms
      end
    end

    context "#correction_coefficient" do
      should "return 0.0 when no correction coefficient is set" do
        id = "no_cc_test"
        instance = Subject.new(id, DUMMY_ALGO)
        instance.redis_client.del(instance.correction_coefficient_key)
        assert_equal 0.0, instance.correction_coefficient
      end

      should "return the expected correction coefficient when available" do
        id = "cc_test"
        instance = Subject.new(id, DUMMY_ALGO)
        expected_value = 5.0
        instance.redis_client.set(instance.correction_coefficient_key, expected_value)
        assert_equal expected_value, instance.correction_coefficient
      end
    end

    context "#correction_coefficient_key" do
      should "return the namespace combined with the coefficient suffix" do
        suffix = Subject.const_get(:COEFFICIENT_SUFFIX)
        instance = Subject.new("id", DUMMY_ALGO)
        assert_equal instance.namespace + suffix, instance.correction_coefficient_key
      end
    end

    context "#decrement_correction_coefficient" do
      should "decrement the value of the correction coefficient key by one" do
        id = "decr_test"
        instance = Subject.new(id, DUMMY_ALGO)
        initial_value = instance.correction_coefficient
        instance.decrement_correction_coefficient
        new_value = instance.correction_coefficient
        assert_equal initial_value - 1, new_value
      end
    end

    context "#increment_correction_coefficient" do
      should "increment the value of the correction coefficient key by one" do
        id = "incr_test"
        instance = Subject.new(id, DUMMY_ALGO)
        initial_value = instance.correction_coefficient
        instance.increment_correction_coefficient
        new_value = instance.correction_coefficient
        assert_equal initial_value + 1, new_value
      end
    end

    context "#lock_key" do
      should "return the namespace combined with the lock suffix" do
        suffix = Subject.const_get(:LOCK_SUFFIX)
        instance = Subject.new("id", DUMMY_ALGO)
        assert_equal instance.namespace + suffix, instance.lock_key
      end
    end

    context "#namespace" do
      should "return the base namespace combined with the id" do
        id = "id"
        base_namespace = Subject.const_get(:BASE_NAMESPACE)
        instance = Subject.new(id, DUMMY_ALGO)
        assert_equal base_namespace + id, instance.namespace
      end
    end

    context "#try_lock" do
      subject { Subject.new("try_lock_test", lambda { |cc| cc * 1000 + 5000 }) }

      should "raise ArgumentError if no block given" do
        instance = subject
        assert_raises(ArgumentError, "block required") do
          instance.try_lock
        end
      end

      should "try to set the lock key only if it doesn't exist and with a TTL in MS" do
        subject.redis_client.set(subject.lock_key, true)
        opts = { :nx => true, :px => subject.calculate_interval_in_ms.to_i }
        subject.redis_client.expects(:set).with(subject.lock_key, true, opts)
        subject.try_lock {}
      end

      should "short-circuit if lock key exists" do
        lock_block_invocation_count = 0
        subject.redis_client.set(subject.lock_key, true)
        result = subject.try_lock do
          lock_block_invocation_count += 1
        end
        assert_equal 0, lock_block_invocation_count
        assert_equal false, result
      end

      should "invoke the lock block if the lock key does not exist" do
        lock_block_invocation_count = 0
        subject.redis_client.del(subject.lock_key)
        yielded_gov = nil
        result = subject.try_lock do |gov|
          lock_block_invocation_count += 1
          yielded_gov = gov
        end
        assert_equal 1, lock_block_invocation_count
        assert_equal subject, yielded_gov
        assert_equal true, result
        msg = "Expected lock TTL to be greater than 0"
        assert subject.redis_client.ttl(subject.lock_key) > 0, msg
      end
    end
  end
end
