# frozen_string_literal: true

# Makes a detector raise the way a real bug would, wherever discovery runs it,
# so specs can check that missing facts are never read as absent ones.
module CrashingDetector
  def crash(detector, error = ArgumentError.new("boom"))
    allow(Reanimator.logger).to receive(:warn)
    crashed = instance_double(detector)
    allow(crashed).to receive(:call).and_raise(error)
    allow(detector).to receive(:new).and_return(crashed)
  end
end
