package = "api-umbrella"

version = "git-1"
source = {
  url = "git+https://github.com/NREL/api-umbrella.git"
}

dependencies = {
  "argparse ~> 0.7.1",
  "bcrypt ~> 2.3",
  "dkjson ~> 2.8",
  "inspect ~> 3.1.3",
  "lapis ~> 1.17.0",
  "libcidr-ffi ~> 1.0.0",
  "lua-resty-http ~> 0.17.2",
  "lua-resty-mail ~> 1.2.0",
  "lua-resty-mlcache ~> 2.7.0",
  "lua-resty-nettle ~> 2.1",
  "lua-resty-openidc ~> 1.7.6",
  "lua-resty-session ~> 3.10",
  "lua-resty-txid ~> 1.0.0",
  "lua-resty-uuid ~> 1.1",
  "lua-resty-validation ~> 2.7",
  "luajit-zstd ~> 0.2.3",
  "lualdap ~> 1.4.0",
  "luaposix ~> 36.3",
  "luautf8 ~> 0.2.0",
  "lustache ~> 1.3.1",
  "lyaml ~> 6.2.8",
  "penlight ~> 1.15.0",
  "psl ~> 0.3",
  "shell-games ~> 1.1.0",
}

build = {
  type = "builtin",
  modules = {},
}
