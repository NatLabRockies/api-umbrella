package = "api-umbrella-test"

version = "git-1"
source = {
  url = "git+https://github.com/NREL/api-umbrella.git"
}

dependencies = {
  "lua >= 5.1",
  "luacheck ~> 1.2.0",
  "luaposix ~> 36.3",
  "penlight ~> 1.15.0",
  "shell-games ~> 1.1.0",
}

build = {
  type = "builtin",
  modules = {},
}
