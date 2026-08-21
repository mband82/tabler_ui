# frozen_string_literal: true

require "rails_helper"

# star-rating.js and apexcharts.js are vendored as classic UMD bundles: they
# build their public class but never emit an ES `export`. rating_controller.js
# and chart_controller.js load them via a dynamic `import("star-rating.js")` /
# `import("apexcharts")`, which needs a real module export to resolve --
# without one `module.default` is undefined and `new this.StarRating(...)` /
# `new this.ApexCharts(...)` throw "is not a constructor" at runtime (the
# rating component's JS has never worked because of exactly this).
#
# Both files get one line hand-appended, purely to turn them into valid ES
# modules -- see the comment above each `export default` line in the vendored
# files themselves. Rule 7 exempts Stimulus JS from specs, and there is no JS
# test toolchain here, so nothing else would catch a future re-vendor (copying
# in a fresh upstream build) silently dropping that line. This spec is the
# guard.
RSpec.describe "vendored ES module exports" do
  let(:javascripts_dir) do
    File.expand_path("../../../app/assets/javascripts", __dir__)
  end

  it "star-rating.js still declares StarRating as a plain module-scope var" do
    contents = File.read(File.join(javascripts_dir, "star-rating.js"))

    expect(contents).to match(/\Avar StarRating = \(function/)
  end

  it "star-rating.js exports its StarRating class as the module default" do
    contents = File.read(File.join(javascripts_dir, "star-rating.js"))

    expect(contents).to include("export default StarRating;")
  end

  it "apexcharts.js exports ApexCharts (via the UMD build's own globalThis assignment) as the module default" do
    contents = File.read(File.join(javascripts_dir, "apexcharts.js"))

    expect(contents).to include("export default globalThis.ApexCharts;")
  end
end
