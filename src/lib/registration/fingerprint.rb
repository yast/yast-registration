module Registration
  class Fingerprint
    attr_reader :sum, :value

    SHA1 = "SHA1".freeze
    SHA256 = "SHA256".freeze

    def initialize(sum, value)
      @sum = sum
      @value = value
    end

    def ==(other)
      return false if other.nil?

      # case insensitive compare of the fingerprint value
      # (ignore optional colon separators)
      sum.casecmp(other.sum) == 0 && value.tr(":", "").casecmp(other.value.tr(":", "")) == 0
    end
  end
end
