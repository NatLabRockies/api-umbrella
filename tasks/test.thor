# vi: set ft=ruby :

class Test < Thor
  desc "test", "Run tests"
  def test
    tests = ["test"]
    if ENV["TESTS"]
      tests = ENV.fetch("TESTS").split(" ")
    end

    exec "bundle", "exec", "minitest", *tests
  end
end
